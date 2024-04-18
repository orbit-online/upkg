#!/usr/bin/env bash
# shellcheck disable=2059,2064
set -eo pipefail
shopt -s inherit_errexit

upkg() {
  [[ ! $(bash --version | head -n1) =~ version\ [34]\.[0-3] ]] || fatal "upkg requires bash >= v4.4"
  WGET_FORUND=false CURL_FOUND=false
  type wget &>/dev/null && WGET_FORUND=true
  type curl &>/dev/null && CURL_FOUND=true
  $WGET_FORUND || $CURL_FOUND || fatal 'Unable to find http fetch depency, neither wget nor curl was found.'

  local dep; for dep in jq git shasum tar; do type "$dep" >/dev/null 2>&1 || \
    fatal "Unable to find dependency '%s'." "$dep"; done
  export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -oBatchMode=yes"} DRY_RUN=false
  DOC="μpkg - A minimalist package manager
Usage:
  upkg install [-n] [-g [giturl]user/pkg@<version>]
  upkg install [-n] [-g tarballurl@<sha256sum>]
  upkg uninstall -g user/pkg
  upkg list [-g]
  upkg -h

Options:
  -g  Act globally
  -n  Dry run, \$?=1 if install/upgrade is required
  -h  Shows extended help message with examples and specifications"
  local prefix=$HOME/.local pkgspath pkgpath tmppkgspath
  pkgpath=$(realpath "$PWD")
  [[ $EUID != 0 ]] || prefix=/usr/local
  case "$1" in
    install)
      [[ $2 != -n ]] || { DRY_RUN=true; shift; }
      if [[ $# -eq 3 && $2 = -g ]]; then
        (upkg_install "$3" "$prefix/lib/upkg" "$prefix/bin" >/dev/null)
        if $DRY_RUN; then processing '%s is up-to-date' "$3"; else processing 'Installed %s' "$3"; fi
        [[ ! -t 2 ]] || { ${UPKG_SILENT:-false} || printf "\n";}
      elif [[ $# -eq 1 ]]; then
        deps=$(jq -r '(.dependencies // []) | to_entries[] | "\(.key)@\(.value)"' <"$pkgpath/upkg.json")
        local installed_deps removed_pkgs dep
        installed_deps=$(upkg_install "$deps" "$pkgpath/.upkg" "$pkgpath/.upkg/.bin")
        [[ ! -e "$pkgpath/.upkg" ]] || removed_pkgs=$(comm -13 <(sort <<<"$installed_deps") <(find "$pkgpath/.upkg" \
          -mindepth 2 -maxdepth 2 -not -path "$pkgpath/.upkg/.bin/*" | rev | cut -d/ -f-2 | rev | sort))
        while [[ -n $removed_pkgs ]] && read -r -d $'\n' dep; do
          upkg_uninstall "$dep" "$pkgpath/.upkg" "$pkgpath/.upkg/.bin"
        done <<<"$removed_pkgs"
        if $DRY_RUN; then processing 'All dependencies up-to-date'; else processing 'Installed all dependencies'; fi
        [[ ! -t 2 ]] || { ${UPKG_SILENT:-false} || printf "\n";}
      else fatal "$DOC"; fi ;;
    uninstall)
      [[ $# -eq 3 && $2 = -g ]] || fatal "$DOC"
      [[ $3 =~ ^([^@/: ]+/[^@/: ]+)$ ]] || fatal "Expected packagename ('user/pkg') not '%s'" "$3"
      upkg_uninstall "$3" "$prefix/lib/upkg" "$prefix/bin"
      processing 'Uninstalled %s' "$3" && { [[ ! -t 2 ]] || { ${UPKG_SILENT:-false} || printf "\n";} } ;;
    list)
      if [[ $# -eq 2 && $2 = -g ]]; then
        upkg_list "$prefix/lib/upkg" false
      elif [[ $# -eq 1 ]]; then
        upkg_list "$pkgpath/.upkg" true
      else fatal "$DOC"; fi ;;
    help|--help|-h)
      fatal "$DOC

Examples:
  Installing from git repo using github shorthand:
    upkg install -g orbit-online/records.sh@v0.9.5

  Installing from git repo with giturl:
    upkg install -g https://github.com/orbit-online/records.sh.git@v0.9.5

  Installing from tarballurl:
    upkg install -g https://organization.s3.amazonaws.com/optional/namespace/pkgname-v0.3.1.tar.gz@69ac88324957d3efaa2616855c657be2de48e840b023282367b41c2f5f73ebcd

Specifications:
  tarballurl:
    <protocol>://[subdomain.]*domain.tld/[pathname/]*<pkgname>-v<pkgversion>.tar[.compression-extension][?GET-params...]@<sha256sum>

    For <protocol> http and https is supported, it comes down to what wget/curl supports
    Compression extensions supported comes down to what \`tar xf\` can auto detect, e.g. .gz, .bz2, .xz etc.

    <pkgversion> is only a symbolic notion used when listing packages, and must be prefixed with a \`v\`

    The filesystem location and effective pkgname is calculated from the tarballurl in the following manner.
      .upkg/lib/[subdomain.]domain.tld/[pathname.replace('/','.').]<pkgname>/bin/*

      Considering https://organization.s3.amazonaws.com/optional/namespace/pkgname-v0.3.1.tar.gz
      with tarball content of \`bin/cli-tool\` the filesystem layout will effectively be:

        .upkg/lib/organization.s3.amazonaws.com/optional.namespace.pkgname/bin/cli-tool
        .upkg/.bin/cli-tool -> ../lib/organization.s3.amazonaws.com/optional.namespace.pkgname/bin/cli-tool

      Considering https://raw.githubusercontent.com/pkgname-v0.3.1.tar.gz
      with tarball content of \`bin/cli-tool\` the filesystem layout will effectively be:

        .upkg/lib/raw.githubusercontent.com/pkgname/bin/cli-tool
        .upkg/.bin/cli-tool -> ../lib/raw.githubusercontent.com/pkgname/bin/cli-tool" ;;
    *) fatal "$DOC" ;;
  esac
}

upkg_install() {
  local repospecs=$1 pkgspath=${2:?} binpath=${3:?} tmppkgspath=$4 parent_deps_sntl repospec deps repourl ret=0 \
    dep_pid dep_pids=()
  if [[ -z $4 ]]; then
    tmppkgspath=$(mktemp -d); trap "rm -rf \"$tmppkgspath\"" EXIT
    PREPARATION_LOCK=$tmppkgspath/.preparation-lock # Global lock which is shared until all preparation is done
    INSTALL_LOCK=$tmppkgspath/.install-lock # Global lock which is held exclusively until all preparation is done
    touch "$INSTALL_LOCK" "$PREPARATION_LOCK"
    exec 9<>"$INSTALL_LOCK"; flock -x 9
  else
    test -e "$INSTALL_LOCK" # Make sure other procs haven't errored out before starting work
    parent_deps_sntl="$(dirname "$tmppkgspath").deps-sntl" # Sentinel from the parent pkg (see $deps_sntl)
    until [[ -e "$parent_deps_sntl" ]]; do sleep .01; done
  fi
  local deps_lock=$tmppkgspath/.deps-lock # Local lock which is shared during preparation of all deps on this level
  local locks_acq_sntl=$tmppkgspath/.locks-sntl # Per loop sentinel that exists until all locks have been acquired
  mkdir -p "$tmppkgspath"; touch "$deps_lock"
  while [[ -n $repospecs ]] && read -r -d $'\n' repospec; do
    if [[ $repospec =~ ^([^@/: ]+/[^@/: ]+)(@([^@ ]+))$ ]]; then
      repourl="https://github.com/${BASH_REMATCH[1]}.git"
    elif [[ $repospec = https://github.com/* ]]; then
      repourl=${repospec%@*}
    elif [[ $repospec =~ ([^@/: ]+/[^@/ ]+)(@([0-9a-f]{64}))$ ]]; then
      upkg_install_tar "${repospec%@*}" "${BASH_REMATCH[3]}" "$pkgspath" "$binpath" "$tmppkgspath"
      continue
    else
      fatal "Unable to parse repospec '%s'. Expected a git cloneable URL followed by @version or tarball URL followed by @version (sha256sum)" "$repospec"
    fi
    local pkgname="${BASH_REMATCH[1]%\.git}" pkgversion="${BASH_REMATCH[3]}"
    local pkgpath="$pkgspath/$pkgname" tmppkgpath=$tmppkgspath/$pkgname curversion deps out
    mkdir -p "$(dirname "$tmppkgpath")"
    local deps_sntl="$tmppkgpath.deps-sntl" # Sentinel that exists until all dependencies of this pkg have been prepared
    touch "$locks_acq_sntl"
    ( exec 8<>"$PREPARATION_LOCK"; flock -sn 8 # Automatically released once this subshell exits
      exec 7<>"$deps_lock"; flock -sn 7 # Automatically released once this subshell exits
      touch "$deps_sntl"
      rm "$locks_acq_sntl" # All locks acquired
      while [[ -e $deps_sntl ]]; do sleep .01; done )& # Release locks once all deps have finished preparing
    while [[ -e $locks_acq_sntl ]]; do sleep .01; done
    ( [[ ! -e "$pkgpath/upkg.json" ]] || curversion=$(jq -r '.version' <"$pkgpath/upkg.json")
    # Ensure deps sentinel is removed if we error out before calling upkg_install, also signal error to all other procs
    trap "rm -f \"$deps_sntl\" \"$INSTALL_LOCK\"" ERR
    if [[ $curversion = refs/heads/* || $pkgversion != "${curversion#'refs/tags/'}" ]]; then
      ! $DRY_RUN || fatal "%s is not up-to-date" "$pkgname"
      [[ ! -e "$pkgpath" || -w "$pkgpath" ]] || \
        fatal "The destination ('%s') for the package '%s' is not writable." "$pkgpath" "$pkgname"
      processing 'Fetching %s@%s' "$pkgname" "$pkgversion"
      local ref_is_sym=false gitargs=() upkgjson upkgversion asset assets command commands cmdpath
      upkgversion=$(git ls-remote -q "$repourl" "$pkgversion" | cut -d$'\t' -f2 | head -n1)
      if [[ -n "$pkgversion" && -n $upkgversion ]]; then
        ref_is_sym=true gitargs=(--depth=1 "--branch=$pkgversion")  # version is a ref, we can make a shallow clone
      fi
      [[ $upkgversion = refs/* ]] || upkgversion=$pkgversion
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
        if [[ $asset = /* || $asset =~ /\.\.(/|$)|//|^.upkg(/|$) || ! -e "$tmppkgpath/$asset" ]]; then
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
        if [[ -e $cmdpath && $(realpath "$cmdpath") != $pkgpath/* ]]; then
          fatal "Error on command '%s' in package %s@%s. The 'bin/' file/symlink exists \
and does not point to the package" "$command" "$pkgname" "$pkgversion"
        fi
      done <<<"$commands"
      deps=$(jq -r '(.dependencies // []) | to_entries[] | "\(.key)@\(.value)"' <<<"$upkgjson")
      local installed_deps removed_pkgs
      installed_deps=$(upkg_install "$deps" "$pkgpath/.upkg" "$pkgpath/.upkg/.bin" "$tmppkgpath/.upkg")

      exec 6<>"$INSTALL_LOCK"; flock -s 6; test -e "$INSTALL_LOCK" # Wait until we can install
      processing 'Installing %s@%s' "$pkgname" "$pkgversion"
      if [[ -e $pkgpath/upkg.json ]]; then # Remove package before reinstalling
        [[ ! -e "$pkgpath/.upkg" ]] || removed_pkgs=$(comm -13 <(sort <<<"$installed_deps") <(find "$pkgpath/.upkg" \
          -mindepth 2 -maxdepth 2 -not -path "$pkgpath/.upkg/.bin/*" | rev | cut -d/ -f-2 | rev | sort))
        [[ -n $removed_pkgs ]] || removed_pkgs='-'
        upkg_uninstall "$pkgname" "$pkgspath" "$binpath" "$removed_pkgs"
      fi
      while [[ -n $assets ]] && read -r -d $'\n' asset; do
        mkdir -p "$(dirname "$pkgpath/$asset")"
        cp -a "$tmppkgpath/$asset" "$pkgpath/$asset"
      done <<<"$assets"
      if [[ -n $commands ]]; then
        mkdir -p "$binpath"
        while [[ -n $commands ]] && read -r -d $'\n' command; do
          read -r -d $'\n' asset
          if [[ $pkgspath = */lib/upkg ]]; then
            ln -sf "../lib/upkg/$pkgname/$asset" "$binpath/$command" # Overwrite to support unclean uninstalls
          else
            ln -sf "../$pkgname/$asset" "$binpath/$command"
          fi
        done <<<"$commands"
      fi
      printf "%s\n" "$upkgjson" >"$pkgpath/upkg.json"
    else
      if $DRY_RUN; then [[ -t 2 ]] || processing '%s@%s is up-to-date' "$pkgname" "$pkgversion"
      else processing 'Skipping %s@%s' "$pkgname" "$pkgversion"; fi
      deps=$(jq -r '(.dependencies // []) | to_entries[] | "\(.key)@\(.value)"' <"$pkgpath/upkg.json")
      (upkg_install "$deps" "$pkgpath/.upkg" "$pkgpath/.upkg/.bin" "$tmppkgpath/.upkg" >/dev/null)
    fi
    printf "%s\n" "$pkgname" )&
    dep_pids+=($!)
  done <<<"$repospecs"
  exec 5<>"$deps_lock"; flock -x 5; rm "$deps_lock" # All pkgs and their deps in the above loop have been prepared
  if [[ -z $4 ]]; then
    exec 4<>"$PREPARATION_LOCK"; flock -x 4; rm "$PREPARATION_LOCK" # Wait until all preparations are done
    flock -u 9 # All preparations are done, signal install can proceed (for some reason 'exec 9>&-' doesn't work)
  else
    rm "$parent_deps_sntl" # Signal to the parent pkg that all deps are prepared
  fi
  for dep_pid in "${dep_pids[@]}"; do wait "$dep_pid" || ret=$?; done
  return $ret
}

upkg_fetch() {
  local url="$1" dst="$2" out
  if $WGET_FORUND; then
    out=$(wget --server-response -qO "$dst" "$url" 2>&1) || fatal 'Could not download depency %s\n\n%s' "$url" "$out"
  elif $CURL_FOUND; then
    curl -fsLo "$dst" "$url" || fatal 'Could not download depency %s' "$url"
  else
    fatal 'Invalid invariant, no http fetch engine found.'
  fi
}

upkg_install_tar() {
  local url=$1 sha256sum=$2 pkgspath=${3:?} binpath=${4:?} tmppkgspath=$5 \
        baseurl dirname domain filename pathname protocol \
        pkgfsname pkgname pkgpath pkgversion

  baseurl="${url%'?'*}"                     # https://orbit-binaries.s3.eu-west-1.amazonaws.com/secoya/orbit-cli-v0.1.0.tar.gz
  protocol="${baseurl%%'//'*}//"            # https://
  domain="${baseurl#"$protocol"}"           # *intermediate* removing protocol from baseurl
  domain="${domain%%'/'*}"                  # orbit-binaries.s3.eu-west-1.amazonaws.com
  pathname="${baseurl#"$protocol$domain/"}" # secoya/orbit-cli-v0.1.0.tar.gz
  dirname="$(dirname "$pathname")"          # secoya
  filename="$(basename "$pathname")"        # orbit-cli-v0.1.0.tar.gz
  pkgname="${filename%'-v'*}"               # orbit-cli
  pkgversion="${filename#"${pkgname}-"}"    # *intermediate* removing pkgname and dash from filename
  pkgversion="${pkgversion%.tar*}"          # v0.1.0

  [[ $pkgversion != v* ]] && fatal 'Could not determine pkgversion for %s, found %s' "$url" "$pkgversion"
  [[ $dirname == '.' ]] && pkgfsname="$domain/$pkgname" || pkgfsname="$domain/${dirname//\//.}.$pkgname"

  local pkgpath="$pkgspath/$pkgfsname" tmppkgpath=$tmppkgspath/$pkgfsname
  mkdir -p "$(dirname "$tmppkgpath")"

  processing 'Fetching %s@%s' "$pkgfsname" "$pkgversion"
  upkg_fetch "$url" "$tmppkgpath" || return $?

  local out
  out="$(echo "$sha256sum  $tmppkgpath" | shasum -a 256 -c -)" || fatal "sha256sum mismatch: %s, did not match %s" "$url" "$sha256sum"
  tar -tf "$tmppkgpath" | grep -qE '^bin/' || fatal "Invalid upkg tarball, top-level bin/ directory wasn't found, got:\n%s" "$(tar -tf "$tmppkgpath")"

  processing 'Installing %s@%s' "$pkgfsname" "$pkgversion"
  mkdir -p "$pkgpath" "$binpath"
  (cd "$pkgpath" && tar -xf "$tmppkgpath") || return $?

  local command
  for command in "$pkgpath/bin"/*; do
    if test -x "$command"; then
      command="$(basename "$command")"
      if [[ $pkgspath = */lib/upkg ]]; then
        ln -sf "../lib/upkg/$pkgfsname/bin/$command" "$binpath/$command" # Overwrite to support unclean uninstalls
      else
        ln -sf "../$pkgfsname/bin/$command" "$binpath/$command"
      fi
    fi
  done

  jq --null-input --arg version "$pkgversion" --arg sha256sum "$sha256sum" '{"version": $version, "sha256sum": $sha256sum}' >"$pkgpath/upkg.json"
  printf -- '%s\n' "$pkgfsname" # report the package is installed.

  return 0
}

upkg_uninstall() {
  local pkgname=${1:?} pkgspath=${2:?} binpath=${3:?} deps_to_remove=$4 dep
  processing 'Uninstalling %s' "$pkgname"
  local pkgpath="$pkgspath/$pkgname" asset command commands cmdpath
  [[ -e "$pkgpath/upkg.json" ]] || { processing "'%s' is not installed" "$pkgname"; return 0; }
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

processing() {
  ! ${UPKG_SILENT:-false} || return 0
  local tpl=$1; shift
  { [[ -t 2 ]] && printf -- "\e[2Kupkg: $tpl\r" "$@" >&2; } || printf -- "upkg: $tpl\n" "$@" >&2
}

fatal() {
  local tpl=$1; shift
  printf -- "upkg: $tpl\n" "$@" >&2
  return 1
}

upkg "$@"
