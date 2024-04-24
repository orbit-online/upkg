#!/usr/bin/env bash
# shellcheck disable=2059,2064
set -eo pipefail
shopt -s inherit_errexit

upkg() {
  [[ ! $(bash --version | head -n1) =~ version\ [34]\.[0-3] ]] || fatal "upkg requires bash >= v4.4"
  local dep; for dep in jq git; do type "$dep" >/dev/null 2>&1 || \
    fatal "Unable to find dependency '%s'." "$dep"; done
  export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -oBatchMode=yes"} DRY_RUN=false
  DOC="μpkg - A minimalist package manager
Usage:
  upkg add [-g] URL [checksum]
  upkg remove [-g] PKGNAME
  upkg list [-g]
  upkg install [-n]

Options:
  -g  Act globally
  -n  Dry run, \$?=1 if install/upgrade is required"
  if [[ -n $INSTALL_PREFIX ]]; then
    INSTALL_PREFIX=$HOME/.local
    [[ $EUID != 0 ]] || INSTALL_PREFIX=/usr/local
  fi
  unset TMPPATH
  local cmd=$1
  shift
  case "$cmd" in
    add)
      local pkgpath=$PWD
      if [[ $# -ge 2 && $1 = -g ]]; then
        pkgpath=$INSTALL_PREFIX/lib/upkg
        shift
      fi
      [[ $# -eq 1 || $# -eq 2 ]] || fatal "$DOC"
      upkg_add "$pkgpath" "$1" "$2"
      ;;
    remove)
      local pkgpath=$PWD
      if [[ $# -eq 2 && $1 = -g ]]; then
        pkgpath=$INSTALL_PREFIX/lib/upkg
        shift
      fi
      [[ $# -eq 1 ]] || fatal "$DOC"
      upkg_remove "$pkgpath" "$1"
      ;;
    list)
      if [[ $# -eq 1 && $1 = -g ]]; then
        upkg_list "$INSTALL_PREFIX/lib/upkg" false
      elif [[ $# -eq 0 ]]; then
        upkg_list "$pkgpath/.upkg" true
      else
        fatal "$DOC"
      fi
      ;;
    install)
      DRY_RUN=false
      [[ $1 != -n ]] || { DRY_RUN=true; shift; }
      [[ $# -eq 0 ]] || fatal "$DOC"
      upkg_install "$PWD"
      ;;
    *) fatal "$DOC" ;;
  esac
  [[ ! -t 2 ]] || { ${UPKG_SILENT:-false} || printf "\n";}
}

upkg_add() {
  local pkgpath=$1 pkgurl=$2 checksum=$3
  local upkgjson={}
  [[ ! -e "$pkgpath/upkg.json" ]] || upkgjson=$(cat "$pkgpath/upkg.json")
  if jq -re --arg pkgurl "$pkgurl" '.dependencies[$pkgurl] // empty' <<<"$upkgjson" >/dev/null; then
    fatal "The package has already been added, run \`upkg remove %s\` first if you want to update it" "$(basename "$pkgurl")"
  fi
  if [[ -z "$checksum" ]]; then
    processing "No checksum given for '%s', determining now" "$pkgurl"
    if [[ $pkgurl =~ (\.tar(\.[^.?#/]+)?)(\?|$) ]]; then
      upkg_mktemp
      mkdir -p "$TMPPATH/prefetched"
      local tmp_archive="$TMPPATH/prefetched/temp-archive"
      upkg_fetch "$pkgurl" "$tmp_archive"
      checksum=$(shasum -a 256 "$tmp_archive" | cut -d ' ' -f1)
      mv "$tmp_archive" "$TMPPATH/prefetched/$checksum"
    else
      if ! checksum=$(git ls-remote -q "$pkgurl" HEAD | grep $'\tHEAD$' | cut -f1); then
        fatal "Unable to determine remote HEAD for '%s', assumed git repo from URL" "$pkgurl"
      fi
    fi
  fi
  upkgjson=$(jq --arg url "$pkgurl" --arg checksum "$checksum" '.dependencies[$url]=$checksum' <<<"$upkgjson")
  printf "%s\n" "$upkgjson" >"$pkgpath/upkg.json"
  upkg_install "$pkgpath"
}

upkg_remove() {
  local pkgpath=$1 pkgname=$2 dep
  processing "Removing '%s'" "$pkgname"
  local pkgurl upkgjson
  pkgurl=$(upkg_get_pkg_url "$pkgpath" "$pkgname")
  upkgjson=$(jq -r --arg pkgurl "$pkgurl" 'del(.dependencies[$pkgurl])' "$pkgpath/upkg.json")
  printf "%s\n" "$upkgjson" >"$pkgpath/upkg.json"
  upkg_install "$pkgpath"
  processing "Removed '%s'" "$pkgname"
}

upkg_list() {
  local pkgspath=${1:-} recursive=${2:?} indent=${3:-''} pkgpath pkgpaths pkgname pkgversion upkgversion
  pkgpaths=$(find "$pkgspath" -mindepth 2 -maxdepth 2 -not -path "$pkgspath/.bin/*")
  while [[ -n $pkgpaths ]] && read -r -d $'\n' pkgpath; do
    pkgname=${pkgpath#"$pkgspath/"} upkgversion="$(jq -r .version <"$pkgpath/upkg.json")"
    pkgversion=${upkgversion#'refs/heads/'}
    pkgversion=${pkgversion#'refs/tags/'}
    printf "%s%s@%s\n" "$indent" "$pkgname" "$pkgversion"
    if $recursive && [[ -e "$pkgpath/.upkg" ]]; then
      upkg_list "$pkgpath/.upkg" "$recursive" "$indent  "
    fi
  done <<<"$pkgpaths"
}

upkg_install() {
  local pkgpath=$1
  [[ -e "$pkgpath/upkg.json" ]] || fatal "No upkg.json found in '%s'" "$pkgpath"
  upkg_mktemp
  mkdir "$TMPPATH/root"
  DEDUPPATH="$pkgpath/.upkg/.packages"
  upkg_install_deps "$TMPPATH/root" "$pkgpath"
  if [[ $pkgpath = "$INSTALL_PREFIX/lib/upkg" ]]; then
    local available_cmds global_cmds cmd
    available_cmds=$(upkg_list_available_cmds "$TMPPATH/root" | sort)
    global_cmds=$(upkg_list_global_referenced_cmds "$INSTALL_PREFIX" | sort)
    while read -r -d $'\n' cmd; do
      [[ -e "$INSTALL_PREFIX/bin/$cmd" ]] || \
        fatal "conflict: the command '%s' already exists in '%s' but does not point to '%s'" \
          "$cmd" "$INSTALL_PREFIX/bin" "$INSTALL_PREFIX/lib/upkg"
    done < <(comm -23 <(printf "%s\n" "$available_cmds") <(printf "%s\n" "$global_cmds"))
    while read -r -d $'\n' cmd; do
      processing "Linking '%s'" "$cmd"
      ln -s "../lib/upkg/.upkg/.bin/$cmd" "$INSTALL_PREFIX/bin/$cmd"
    done < <(comm -23 <(printf "%s\n" "$available_cmds") <(printf "%s\n" "$global_cmds"))
    while read -r -d $'\n' cmd; do
      rm "$INSTALL_PREFIX/bin/$cmd"
    done < <(comm -12 <(printf "%s\n" "$available_cmds") <(printf "%s\n" "$global_cmds"))
  fi
  rm -rf "$pkgpath/.upkg/.bin"
  if [[ -e "$TMPPATH/root/.upkg" ]]; then
    [[ ! -e "$pkgpath/.upkg" ]] || find "$pkgpath/.upkg" -mindepth 1 -maxdepth 1 -not -name '.*' -delete
    cp -a "$TMPPATH/root/.upkg" "$pkgpath/"
    upkg_remove_unreferenced_pkgs "$pkgpath"
  else
    rm -rf "$pkgpath/.upkg"
  fi
  processing 'Installed all dependencies'
}

upkg_get_pkg_url() {
  local pkgpath=$1 pkgname=$2 checksum
  [[ -e "$pkgpath/.upkg/$pkgname" ]] || fatal "Unable to find '%s' in '%s'" "$pkgname" "$pkgpath/.upkg"
  checksum=$(readlink "$pkgpath/.upkg/$pkgname")
  checksum=$(basename "$checksum")
  checksum=${checksum#*@}
  if ! jq -re --arg checksum "$checksum" '.dependencies | to_entries[] | select(.value==$checksum) | .key // empty' "$pkgpath/upkg.json"; then
    fatal "'%s' is not listed in '%s'" "$pkgname" "$pkgpath/upkg.json"
  fi
}

upkg_remove_unreferenced_pkgs() {
  local pkgpath=$1 dep_pkgpath cmdpath
  while read -r -d $'\n' dep_pkgpath; do
    rm -rf "$pkgpath/.upkg/$dep_pkgpath"
  done < <(comm -23 <(upkg_list_all_pkgs "$pkgpath" | sort) <(upkg_list_referenced_pkgs "$pkgpath" | sort))
}

upkg_list_all_pkgs() {
  local pkgpath=$1
  (cd "$pkgpath/.upkg/"; find .packages -mindepth 1 -maxdepth 1)
}

upkg_list_referenced_pkgs() {
  local pkgpath=$1 dep_pkgpath
  while read -r -d $'\n' dep_pkgpath; do
    printf "%s\n" "$dep_pkgpath"
    [[ ! -e "$pkgpath/.upkg/$dep_pkgpath/.upkg" ]] || \
      find "$pkgpath/.upkg/$dep_pkgpath/.upkg" -mindepth 1 -maxdepth 1 -not -name '.*' -exec readlink \{\} \;
  done < <(find "$pkgpath/.upkg" -mindepth 1 -maxdepth 1 -not -name '.*' -exec readlink \{\} \;)
}

upkg_list_available_cmds() {
  local pkgroot=$1 cmdpath
  if [[ -e "$pkgroot/.upkg/.bin" ]]; then
    while read -r -d $'\n' cmdpath; do
      printf "%s\n" "${cmdpath#"$pkgroot/.upkg/.bin/"}"
    done < <(find "$pkgroot/.upkg/.bin" -mindepth 1 -maxdepth 1)
  fi
}

upkg_list_global_referenced_cmds() {
  local install_prefix=$1 cmdpath
  while read -r -d $'\n' cmdpath; do
    [[ $cmdpath != ../lib/upkg/.upkg/.bin/* ]] || printf "%s\n" "${cmdpath#'../lib/upkg/.upkg/.bin/'}"
  done < <(find "$install_prefix/bin" -mindepth 1 -maxdepth 1 -exec readlink \{\} \;)
}

upkg_install_deps() {
  local pkgpath=$1 realpkgpath=${2:-$1} deps
  # The `[[ -e ... ]]` is just to save a jq invocation, the proper mutex operation is the `mkdir` below
  [[ ! -e "$realpkgpath/upkg.json" ]] || deps=$(jq -r '(.dependencies // []) | to_entries[] | .key, .value' "$realpkgpath/upkg.json")
  if [[ -n $deps ]] && mkdir "$pkgpath/.upkg" 2>/dev/null; then
    if [[ $pkgpath = "$TMPPATH/root" ]]; then
      mkdir "$pkgpath/.upkg/.packages"
    else
      ln -s ../../ "$pkgpath/.upkg/.packages"
    fi
    local dep_pkgurl dep_checksum
    while read -r -d $'\n' dep_pkgurl; do
      read -r -d $'\n' dep_checksum
      upkg_install_pkg "$dep_pkgurl" "$dep_checksum" "$pkgpath" "$realpkgpath"
    done <<<"$deps"
  fi
}

upkg_install_pkg() {
  local pkgurl=$1 checksum=$2 parentpath=$3 realparentpath=$4 pkgname pkgpath is_dedup=false
  if [[ -e "$DEDUPPATH" ]] && pkgpath=$(compgen -G "$DEDUPPATH/*@$checksum"); then
    processing "Skipping '%s'" "$pkgurl"
    pkgname=${pkgpath#"$DEDUPPATH/"}
    pkgname=${pkgname%"@$checksum"}
    is_dedup=true
  else
    pkgname=$(upkg_download "$pkgurl" "$checksum" "$realparentpath")
    pkgpath="$parentpath/.upkg/.packages/$pkgname@$checksum"
  fi
  if ! ln -s ".packages/$pkgname@$checksum" "$parentpath/.upkg/$pkgname"; then
    fatal "conflict: The package '%s' is depended upon multiple times"
  fi

  local command cmdpath
  if [[ -e "$pkgpath/bin" ]]; then
    mkdir -p "$parentpath/.upkg/.bin"
    while read -r -d $'\n' command; do
      command=$(basename "$command")
      cmdpath="$parentpath/.upkg/.bin/$command"
      if ! ln -s "../$pkgname/bin/$command" "$cmdpath" 2>/dev/null; then
        local otherpkg
        otherpkg=$(basename "$(dirname "$(dirname "$(readlink "$cmdpath")")")")
        fatal "conflict: '%s' and '%s' both have a command named '%s'" "$pkgname" "$otherpkg" "$command"
      fi
    done < <(find "$pkgpath/bin" -mindepth 1 -maxdepth 1 -type f -executable)
  fi

  $is_dedup || upkg_install_deps "$pkgpath"
}

upkg_download() (
  local pkgurl=$1 checksum=$2 realparentpath=$3 pkgname
  mkdir -p "$TMPPATH/download"
  local downloadpath=$TMPPATH/download/$checksum
  exec 9<>"$downloadpath.lock"
  local already_downloading=false
  if ! flock -nx 9; then
    already_downloading=true
    flock -s 9
  fi
  if pkgname=$(compgen -G "$TMPPATH/root/.upkg/.packages/*@$checksum"); then
    processing "Already downloaded '%s'" "$pkgurl"
    pkgname=${pkgname##*'/'}
    pkgname=${pkgname%@*}
    printf "%s\n" "$pkgname"
    return 0
  elif $already_downloading; then
    return 1
  fi
  mkdir "$downloadpath"
  mkdir -p "$TMPPATH/root/.upkg/.packages"
  if [[ $pkgurl =~ (\.tar(\.[^.?#/]+)?)(\?|$) ]]; then
    local archivepath=${downloadpath}${BASH_REMATCH[1]}
    [[ $checksum =~ ^[a-z0-9]{64}$ ]] || fatal "Checksum for '%s' is not sha256 (64 hexchars), assumed tar archive from URL"
    if [[ -e "$TMPDIR/prefetched/$checksum" ]]; then
      archivepath="$TMPDIR/prefetched/$checksum"
    elif [[ ! $pkgurl =~ ^(https?://|ftps?://)* ]]; then
      archivepath=$pkgurl
    else
      upkg_fetch "$pkgurl" "$archivepath"
    fi
    shasum -a 256 -c <(printf "%s  %s" "$checksum" "$archivepath")
    tar -xf "$archivepath" -C "$downloadpath"
    rm "$archivepath"
  else
    [[ $checksum =~ ^[a-z0-9]{40}$ ]] || fatal "Checksum for '%s' is not sha1 (40 hexchars), assumed git repo from URL"
    processing 'Cloning %s' "$pkgurl"
    local out
    out=$(cd "$realparentpath"; git clone -q "$pkgurl" "$downloadpath" 2>&1) || \
      fatal "Unable to clone '%s'. Error:\n%s" "$pkgurl" "$out"
    out=$(git -C "$downloadpath" checkout -q "$checksum" -- 2>&1) || \
      fatal "Unable to checkout '%s' from '%s'. Error:\n%s" "$checksum" "$pkgurl" "$out"
    if [[ -e "$downloadpath/upkg.json" ]]; then
      local version upkgjson
      version=$(git -C "$downloadpath" describe 2>/dev/null) || version=$checksum
      upkgjson=$(jq --arg version "$version" '.version = $version' <"$downloadpath/upkg.json" || \
        fatal "The package from '%s' does not contain a valid upkg.json" "$pkgurl" "$pkgname")
      printf "%s\n" "$upkgjson" >"$downloadpath/upkg.json"
    fi
  fi
  if [[ -e "$downloadpath/upkg.json" ]]; then
    pkgname=$(jq -r '.name // empty' "$downloadpath/upkg.json")
    [[ -n $pkgname ]] || fatal "The package from '%s' does not specify a package name in its upkg.json"
    [[ $pkgname =~ ^[^@/]+$ || $pkgname = .* ]] || fatal "The package from '%s' specifies an invalid package name: '%s'" "$pkgname"
  else
    pkgname=$(basename "$pkgurl")
    pkgname=${pkgname%%'?'*}
    pkgname=${pkgname/#./_}
  fi
  mv "$downloadpath" "$TMPPATH/root/.upkg/.packages/$pkgname@$checksum"
  printf "%s\n" "$pkgname"
)

upkg_fetch() {
  local url="$1" dest="$2" out
  processing "Downloading %s" "$url"
  if type wget >/dev/null 2>&1; then
    wget --server-response -qO "$dest" "$url" || fatal "Error while downloading '%s'" "$url"
  elif type curl >/dev/null 2>&1; then
    curl -fsLo "$dest" "$url" || fatal "Error while downloading '%s'" "$url"
  else
    fatal "Unable to download '%s', neither wget nor curl are available" "$url"
  fi
}

upkg_mktemp() {
  if [[ -z $TMPPATH ]]; then
    TMPPATH=$(mktemp -d)
    # trap "rm -rf \"$TMPPATH\"" EXIT
  fi
}

processing() {
  ! ${UPKG_SILENT:-false} || return 0
  local tpl=$1; shift
  if [[ -t 2 ]]; then
    printf -- "\e[2Kupkg: $tpl\r" "$@" >&2
  else
    printf -- "upkg: $tpl\n" "$@" >&2
  fi
}

fatal() {
  local tpl=$1; shift
  printf -- "upkg: $tpl\n" "$@" >&2
  return 1
}

upkg "$@"
