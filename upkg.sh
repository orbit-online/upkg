#!/usr/bin/env bash
# shellcheck disable=2059,2064
set -eo pipefail
shopt -s inherit_errexit

upkg() {
  [[ ! $(bash --version | head -n1) =~ version\ [34]\.[0-3] ]] || fatal "upkg requires bash >= v4.4\n"
  { type jq >/dev/null 2>&1 && type git >/dev/null 2>&1; } || fatal "Unable to find dependencies 'jq' and 'git'.\n"
  DOC="μpkg - A minimalist package manager
Usage:
  upkg install
  upkg install -g [remoteurl]user/pkg@<version>
  upkg uninstall -g user/pkg
  upkg list [-g]
  upkg root \${BASH_SOURCE[0]}"
  local prefix=$HOME/.local pkgspath tmppkgspath
  [[ $EUID != 0 ]] || prefix=/usr/local
  case "$1" in
    install)
      tmppkgspath=$(mktemp -d)
      trap "rm -rf \"$tmppkgspath\"" EXIT
      if [[ $# -eq 3 && $2 = -g ]]; then
        upkg_install "$3" "$prefix/lib/upkg" "$prefix/bin" "$tmppkgspath" >/dev/null
        processing 'Installed %s' "$3" && { [[ ! -t 2 ]] || printf "\n"; }
      elif [[ $# -eq 1 ]]; then
        pkgpath=$(upkg_root)
        deps=$(jq -r '(.dependencies // []) | to_entries[] | "\(.key)@\(.value)"' <"$pkgpath/upkg.json")
        upkg_install "$deps" "$pkgpath/.upkg" "$pkgpath/.upkg/.bin" "$tmppkgspath" >/dev/null
        processing 'Installed all dependencies' && { [[ ! -t 2 ]] || printf "\n"; }
      else
        fatal "$DOC"
      fi
      ;;
    uninstall)
      [[ $# -eq 3 && $2 = -g ]] || fatal "$DOC"
      [[ $3 =~ ^([^@/: ]+/[^@/: ]+)$ ]] || fatal "Expected packagename ('user/pkg') not '%s'" "$3"
      upkg_uninstall "$3" "$prefix/lib/upkg" "$prefix/bin"
      processing 'Uninstalled %s' "$3" && { [[ ! -t 2 ]] || printf "\n"; }
      ;;
    list)
      if [[ $# -eq 2 && $2 = -g ]]; then
        upkg_list "$prefix/lib/upkg" false
      elif [[ $# -eq 1 ]]; then
        pkgpath=$(upkg_root)
        upkg_list "$pkgpath/.upkg" true
      else
        fatal "$DOC"
      fi
      ;;
    root)
      [[ -n $2 ]] || fatal "$DOC"
      upkg_root "$2" ;;
    *) fatal "$DOC" ;;
  esac
}

upkg_install() {
  local repospecs=$1 pkgspath=${2:?} binpath=${3:?} tmppkgspath=${4:?} repospec deps repourl
  while [[ -n $repospecs ]] && read -r -d $'\n' repospec; do
    if [[ $repospec =~ ^([^@/: ]+/[^@/: ]+)(@([^@ ]+))$ ]]; then
      repourl="https://github.com/${BASH_REMATCH[1]}.git"
    elif [[ $repospec =~ ([^@/: ]+/[^@/ ]+)(@([^@ ]+))$ ]]; then
      repourl=${repospec%@*}
    else
      fatal "Unable to parse repospec '%s'. Expected a git cloneable URL followed by @version" "$repospec"
    fi
    local pkgname="${BASH_REMATCH[1]%\.git}" pkgversion="${BASH_REMATCH[3]}"
    local pkgpath="$pkgspath/$pkgname" tmppkgpath=$tmppkgspath/$pkgname curversion deps
    [[ ! -e "$pkgpath/upkg.json" ]] || curversion=$(jq -r '.version' <"$pkgpath/upkg.json")
    if [[ $pkgversion != "${curversion#'refs/heads/'}" || $curversion = refs/heads/* ]]; then
      processing 'Installing %s@%s' "$pkgname" "$pkgversion"
      local ref_is_sym=false gitargs=() upkgjson upkgversion asset assets command commands cmdpath installed_deps
      upkgversion=$(git ls-remote -q "$repourl" "$pkgversion" | cut -d$'\t' -f2 | head -n1)
      if [[ -n "$pkgversion" && -n $upkgversion ]]; then
        ref_is_sym=true gitargs=(--depth=1 "--branch=$pkgversion")  # version is a ref, we can make a shallow clone
      fi
      [[ $upkgversion = refs/heads/* ]] || upkgversion=$pkgversion
      out=$(git clone -q "${gitargs[@]}" "$repourl" "$tmppkgpath" 2>&1) || \
        fatal "Unable to clone '%s'. Error:\n%s" "$repospec" "$out"
      $ref_is_sym || out=$(git -C "$tmppkgpath" checkout -q "$pkgversion" -- 2>&1) || \
          fatal "Unable to checkout '%s' from '%s'. Error:\n%s" "$pkgversion" "$repourl" "$out"
      upkgjson=$(jq --arg version "$upkgversion" '.version = $version' <"$tmppkgpath/upkg.json" || \
        fatal "The package '%s' does not contain a valid upkg.json" "$pkgname")
      jq -re '.assets != null or .commands != null or .dependencies != null' <<<"$upkgjson" >/dev/null || \
        fatal "The package '%s' does specify any assets, commands, or dependencies in its upkg.json" "$pkgname"

      assets=$(jq -r '((.assets // []) + [(.commands // {})[]] | unique)[]' <<<"$upkgjson")
      while [[ -n $assets ]] && read -r -d $'\n' asset; do
        [[ ! -d "$tmppkgpath/$asset" || "$tmppkgpath/$asset" = */ ]] || \
          fatal 'Error on asset '%s' in package %s@%s. Directories must have a trailing slash' \
            "$asset" "$pkgname" "$pkgversion"
        if [[ $asset = /* || $asset =~ /\.\.(/|$) || $asset =~ // || $asset =~ ^.upkg(/|$) || ! -e "$tmppkgpath/$asset" ]]; then
          fatal "Error on asset '%s' in package %s@%s.\nAll assets in 'assets' and 'commands' must:
* be relative\n* not contain parent dir parts ('../')\n* not reference the .upkg dir\n* exist in the repository" \
            "$asset" "$pkgname" "$pkgversion"
        fi
      done <<<"$assets"
      commands=$(jq -r '(.commands // {}) | to_entries[] | "\(.key)\n\(.value)"' <<<"$upkgjson")
      while [[ -n $commands ]] && read -r -d $'\n' command; do
        read -r -d $'\n' asset
        [[ -x "$tmppkgpath/$asset" && -f "$tmppkgpath/$asset" ]] || \
          fatal "Error on command '%s' in package %s@%s. The file '%s' does not exist or is not executable" \
            "$command" "$pkgname" "$pkgversion" "$asset"
        [[ ! $command =~ (/| ) ]] || \
          fatal "Error on command '%s' in package %s@%s. The command may not contain spaces or slashes" \
            "$command" "$pkgname" "$pkgversion"
        cmdpath="$binpath/$command"
        if [[ -e $cmdpath || -L $cmdpath ]] && [[ $(realpath "$cmdpath") != $pkgpath/* ]]; then
          fatal "Error on command '%s' in package %s@%s. The symlink for it exists and does not point to the package" \
            "$command" "$pkgname" "$pkgversion"
        fi
      done <<<"$commands"
      deps=$(jq -r '(.dependencies // []) | to_entries[] | "\(.key)@\(.value)"' <<<"$upkgjson")
      installed_deps=$(upkg_install "$deps" "$pkgpath/.upkg" "$pkgpath/.upkg/.bin" "$tmppkgpath/.upkg")

      if [[ -e $pkgpath/upkg.json ]]; then # Remove package before reinstalling
        [[ ! -e "$pkgpath/.upkg" ]] || removed_pkgs=$(comm -13 <(sort <<<"$installed_deps") <(find "$pkgpath/.upkg" \
          -mindepth 2 -maxdepth 2 -not -path "$pkgpath/.upkg/.bin/*" | rev | cut -d/ -f-2 | rev | sort))
        [[ -n $removed_pkgs ]] || removed_pkgs='-'
        upkg_uninstall "$pkgname" "$pkgspath" "$binpath" "$removed_pkgs"
      fi
      while [[ -n $assets ]] && read -r -d $'\n' asset; do
        mkdir -p "$(dirname "$pkgpath/$asset")"
        cp -ar "$tmppkgpath/$asset" "$pkgpath/$asset"
      done <<<"$assets"
      if [[ -n $commands ]]; then
        mkdir -p "$binpath"
        while [[ -n $commands ]] && read -r -d $'\n' command; do
          read -r -d $'\n' asset
          ln -s "$pkgpath/$asset" "$binpath/$command"
        done <<<"$commands"
      fi
      printf "%s\n" "$upkgjson" >"$pkgpath/upkg.json"
    else
      processing 'Skipping %s@%s' "$pkgname" "$pkgversion"
      deps=$(jq -r '(.dependencies // []) | to_entries[] | "\(.key)@\(.value)"' <"$pkgpath/upkg.json")
      upkg_install "$deps" "$pkgpath/.upkg" "$pkgpath/.upkg/.bin" "$tmppkgpath/.upkg" >/dev/null
    fi
    printf "%s\n" "$pkgname"
  done <<<"$repospecs"
}

upkg_uninstall() {
  local pkgname=${1:?} pkgspath=${2:?} binpath=${3:?} deps_to_remove=$4 dep
  processing 'Uninstalling %s' "$pkgname"
  local pkgpath="$pkgspath/$pkgname" asset command commands cmdpath
  [[ -e "$pkgpath/upkg.json" ]] || fatal "'%s' is not installed" "$pkgname"
  commands=$(jq -r '(.commands // {}) | to_entries[] | "\(.key)\n\(.value)"' <"$pkgpath/upkg.json")
  while [[ -n $commands ]] && read -r -d $'\n' command; do
    read -r -d $'\n' asset
    cmdpath="$binpath/$command"
    [[ ! -e $cmdpath || $(realpath "$cmdpath") != $pkgpath/* ]] || rm "$cmdpath"
  done <<<"$commands"
  if [[ -n $deps_to_remove ]]; then
    find "$pkgpath" -mindepth 1 -maxdepth 1 -path "$pkgpath/.upkg" -prune -o -exec rm -rf \{\} \;
    while [[ $deps_to_remove != '-' ]] && read -r -d $'\n' dep; do
      upkg_uninstall "$dep" "$pkgpath/.upkg" "$pkgpath/.upkg/.bin"
    done <<<"$deps_to_remove"
  else
    rm -rf "$pkgpath"
    [[ -n $(find "$(dirname "$pkgpath")" -mindepth 1 -maxdepth 1) ]] || rm -rf "$(dirname "$pkgpath")"
  fi
}

upkg_list() {
  local pkgspath=${1:-} recursive=${2:?} indent=${3:-''} pkgpath pkgpaths pkgname pkgversion
  pkgpaths=$(find "$pkgspath" -mindepth 2 -maxdepth 2 -not -path "$pkgspath/.bin/*")
  while [[ -n $pkgpaths ]] && read -r -d $'\n' pkgpath; do
    pkgname=${pkgpath#"$pkgspath/"} pkgversion="$(jq -r .version <"$pkgpath/upkg.json")"
    printf "%s%s@%s\n" "$indent" "$pkgname" "${pkgversion#refs/heads/}"
    if $recursive && [[ -e "$pkgpath/.upkg" ]]; then
      upkg_list "$pkgpath/.upkg" "$recursive" "$indent  "
    fi
  done <<<"$pkgpaths"
}

upkg_root() (
  local sourcing_file=$1
  [[ -z $sourcing_file ]] || cd "$(dirname "$(realpath "${sourcing_file}")")"
  until [[ -e $PWD/upkg.json ]]; do
    [[ $PWD != '/' ]] ||  fatal 'Unable to find package root (no upkg.json found in this or any parent directory)'
    cd ..
  done
  printf "%s\n" "$PWD"
)

processing() {
  ! ${UPKG_SILENT:-false} || return 0
  local tpl=$1; shift
  { [[ -t 2 ]] && printf -- "\e[2Kupkg: $tpl\r" "$@" >&2; } || printf -- "upkg: $tpl\n" "$@" >&2
}

fatal() {
  local tpl=$1; shift
  printf -- "upkg: $tpl\n" "$@" >&2
  exit 1
}

upkg "$@"
