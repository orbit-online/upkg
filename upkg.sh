#!/usr/bin/env bash

set -e -o pipefail
shopt -s inherit_errexit

upkg() {
  [[ ! $(bash --version | head -n1) =~ version\ [34]\.[0-3] ]] || fatal "upkg: upkg requires bash >= v4.4\n"
  { type jq >/dev/null 2>&1 && type git >/dev/null 2>&1; } || fatal "upkg: Unable to find dependencies 'jq' and 'git'.\n"
  DOC="μpkg - A minimalist package manager
Usage:
  upkg install
  upkg install -g [remoteurl]user/pkg@<version>
  upkg uninstall -g user/pkg
  upkg root \${BASH_SOURCE[0]}
"
  [[ -n $1 ]] || fatal "$DOC"
  local prefix=$HOME/.local pkgspath tmppkgspath
  [[ $EUID != 0 ]] || prefix=/usr/local
  case "$1" in
    install)
      tmppkgspath=$(mktemp -d)
      # shellcheck disable=2064
      trap "rm -rf \"$tmppkgspath\"" EXIT
      if [[ $# -eq 3 && $2 = -g ]]; then
        upkg_install "$3" "$prefix/lib/upkg" "$prefix/bin" "$tmppkgspath"
        printf "upkg: Installed %s\n" "$3" >&2
      elif [[ $# -eq 1 ]]; then
        pkgspath=$(upkg_root)
        deps=$(jq -r '(.dependencies // []) | to_entries[] | "\(.key)@\(.value)"' <"$pkgspath/upkg.json")
        upkg_install "$deps" "$pkgspath/.upkg" "$pkgspath/.upkg/.bin" "$tmppkgspath"
        printf "upkg: Installed all dependencies\n" >&2
      else
        fatal "$DOC"
      fi
      ;;
    uninstall)
      if [[ $# -eq 3 && $2 = -g ]]; then
        [[ $3 =~ ^([^@/: ]+/[^@/: ]+)$ ]] || fatal "upkg: Expected packagename ('user/pkg') not '%s'" "$3"
        upkg_uninstall "$3" "$prefix/lib/upkg" "$prefix/bin"
        printf "upkg: Uninstalled %s\n" "$3" >&2
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
  local repospecs=$1 pkgspath=${2:?} binpath=${3:?} tmppkgspath=${4:?} reinstall=${5:-false} repospec deps
  while [[ -n $repospecs ]] && read -r -d $'\n' repospec; do
    if [[ $repospec =~ ^([^@/: ]+/[^@/: ]+)(@([^@ ]+))$ ]]; then
      local repourl="https://github.com/${BASH_REMATCH[1]}.git"
    elif [[ $repospec =~ ([^@/: ]+/[^@/ ]+)(@([^@ ]+))$ ]]; then
      local repourl=${repospec%@*}
    else
      fatal "upkg: Unable to parse repospec '%s'. Expected a git cloneable URL followed by @version" "$repospec"
    fi
    local pkgname="${BASH_REMATCH[1]}" pkgversion="${BASH_REMATCH[3]}"
    local pkgpath="$pkgspath/$pkgname" tmppkgpath=$tmppkgspath/$pkgname curversion deps
    [[ ! -e "$pkgpath/upkg.json" ]] || curversion=$(jq -r '.version' <"$pkgpath/upkg.json")
    if [[ $pkgversion != "${curversion#'refs/heads/'}" || $curversion = refs/heads/* || $reinstall = true ]]; then
      local ref_is_sym=false gitargs=() upkgjson upkgversion asset assets command commands cmdpath
      upkgversion=$(git ls-remote -q "$repourl" "$pkgversion" | cut -d$'\t' -f2 | head -n1)
      if [[ -n "$pkgversion" && -n $upkgversion ]]; then
        ref_is_sym=true
        gitargs=(--depth=1 "--branch=$pkgversion")  # version is a ref, we can make a shallow clone
      fi
      [[ $upkgversion = refs/heads/* ]] || upkgversion=$pkgversion
      out=$(git clone -q "${gitargs[@]}" "$repourl" "$tmppkgpath" 2>&1) || \
        fatal "upkg: Unable to clone '%s'. Error:\n%s" "$repospec" "$out"
      $ref_is_sym || out=$(git -C "$tmppkgpath" checkout -q "$pkgversion" -- 2>&1) || \
          fatal "upkg: Unable to checkout '%s' from '%s'. Error:\n%s" "$pkgversion" "$repourl" "$out"
      upkgjson=$(jq --arg version "$upkgversion" '.version = $version' <"$tmppkgpath/upkg.json" || \
        fatal "upkg: The package '%s' does not contain a valid upkg.json" "$pkgname")
      jq -re '.assets != null or .commands != null or .dependencies != null' <<<"$upkgjson" >/dev/null || \
        fatal "upkg: The package '%s' does specify any assets, commands, or dependencies in its upkg.json" "$pkgname"

      assets=$(jq -r '((.assets // []) + [(.commands // {})[]] | unique)[]' <<<"$upkgjson")
      while [[ -n $assets ]] && read -r -d $'\n' asset; do
        [[ ! -d "$tmppkgpath/$asset" || "$tmppkgpath/$asset" = */ ]] || \
          fatal 'upkg: Error on asset '%s' in package %s@%s. Directories must have a trailing slash' \
            "$asset" "$pkgname" "$pkgversion"
        if [[ $asset = /* || $asset =~ /\.\.(/|$) || $asset =~ // || $asset =~ ^.upkg(/|$) || ! -e "$tmppkgpath/$asset" ]]; then
          fatal "upkg: Error on asset '%s' in package %s@%s.
All assets in 'assets' and 'commands' must:
* be relative
* not contain parent dir parts ('../')
* not reference the .upkg dir
* exist in the repository" "$asset" "$pkgname" "$pkgversion"
        fi
      done <<<"$assets"
      commands=$(jq -r '(.commands // {}) | to_entries[] | "\(.key)\n\(.value)"' <<<"$upkgjson")
      while [[ -n $commands ]] && read -r -d $'\n' command; do
        read -r -d $'\n' asset
        [[ -x "$tmppkgpath/$asset" && -f "$tmppkgpath/$asset" ]] || \
          fatal "upkg: Error on command '%s' in package %s@%s. The file '%s' does not exist or is not executable" \
            "$command" "$asset" "$pkgname" "$pkgversion"
        [[ ! $command =~ (/| ) ]] || \
          fatal "upkg: Error on command '%s' in package %s@%s. The command may not contain spaces or slashes" \
            "$command" "$pkgname" "$pkgversion"
        cmdpath="$binpath/$command"
        if [[ -e $cmdpath && $(realpath "$cmdpath") != $pkgpath/* ]]; then
          fatal "upkg: Error on command '%s' in package %s@%s. The symlink for it exists and does not point to the package" \
            "$command" "$pkgname" "$pkgversion"
        fi
      done <<<"$commands"
      deps=$(jq -r '(.dependencies // []) | to_entries[] | "\(.key)@\(.value)"' <<<"$upkgjson")
      upkg_install "$deps" "$pkgpath/.upkg" "$pkgpath/.upkg/.bin" "$tmppkgpath/.upkg" true

      [[ ! -e $pkgpath/upkg.json ]] || upkg_uninstall "$pkgname" "$pkgspath" "$binpath"
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
      deps=$(jq -r '(.dependencies // []) | to_entries[] | "\(.key)@\(.value)"' <"$pkgpath/upkg.json")
      upkg_install "$deps" "$pkgpath/.upkg" "$pkgpath/.upkg/.bin" "$tmppkgpath/.upkg" false
    fi
  done <<<"$repospecs"
}

upkg_uninstall() {
  local pkgname=${1:?} pkgspath=${2:?} binpath=${3:?}
  local pkgpath="$pkgspath/$pkgname"
  # When upgrading remove old assets & commands first
  local asset command commands cmdpath
  [[ -e "$pkgpath/upkg.json" ]] || fatal "upkg: '%s' is not installed" "$pkgname"
  commands=$(jq -r '(.commands // {}) | to_entries[] | "\(.key)\n\(.value)"' <"$pkgpath/upkg.json")
  while [[ -n $commands ]] && read -r -d $'\n' command; do
    read -r -d $'\n' asset
    cmdpath="$binpath/$command"
    [[ ! -e $cmdpath || $(realpath "$cmdpath") != $pkgpath/* ]] || rm "$cmdpath"
  done <<<"$commands"
  rm -rf "$pkgpath"
  [[ -n $(find "$(dirname "$pkgpath")" -mindepth 1 -maxdepth 1) ]] || rm -rf "$(dirname "$pkgpath")"
}

upkg_root() (
  local sourcing_file=$1
  [[ -z $sourcing_file ]] || cd "$(dirname "$(realpath "${sourcing_file}")")"
  until [[ -e $PWD/upkg.json ]]; do
    [[ $PWD != '/' ]] || \
      fatal 'upkg root: Unable to find package root (no upkg.json found in this or any parent directory)'
    cd ..
  done
  printf "%s\n" "$PWD"
)

fatal() {
  local tpl=$1; shift
  # shellcheck disable=2059
  printf -- "$tpl\n" "$@" >&2
  exit 1
}

upkg "$@"
