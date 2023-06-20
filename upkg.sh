#!/usr/bin/env bash

set -e -o pipefail
shopt -s inherit_errexit

upkg() {
  [[ ! $(bash --version | head -n1) =~ version\ [34]\.[0-3] ]] || fatal "upkg: upkg requires bash >= v4.4\n"
  if ! type jq >/dev/null 2>&1 || ! type git >/dev/null 2>&1; then
    fatal "upkg: Unable to find dependencies 'jq' and 'git'.\n"
  fi
  DOC="μpkg - A minimalist package manager
Usage:
  upkg install
  upkg install -g [remoteurl]user/pkg@<version>
  upkg uninstall -g user/pkg
  upkg root \${BASH_SOURCE[0]}
"
  [[ -n $1 ]] || fatal "$DOC"
  local subcmd=$1 prefix=$HOME/.local pkgspath tmppkgspath
  [[ $EUID != 0 ]] || prefix=/usr/local
  case "$subcmd" in
    install)
      tmppkgspath=$(mktemp -d)
      # shellcheck disable=2064
      trap "rm -rf \"$tmppkgspath\"" EXIT
      if [[ $# -eq 3 && $2 = -g ]]; then
        upkg_prepare_pkg "$3" "$prefix/lib/upkg" "$prefix/bin" "$tmppkgspath"
        upkg_install_pkg "$3" "$prefix/lib/upkg" "$prefix/bin" "$tmppkgspath"
        printf "upkg: Installed %s\n" "$3" >&2
      elif [[ $# -eq 1 ]]; then
        pkgspath=$(upkg_root)
        upkg_prepare_deps "$pkgspath" "$tmppkgspath" "$pkgspath/upkg.json"
        upkg_install_deps "$pkgspath" "$tmppkgspath"
        printf "upkg: Installed all dependencies\n" >&2
      else
        fatal "$DOC"
      fi
      ;;
    uninstall)
      if [[ $# -ne 3 && $2 = -g ]]; then
        [[ $3 =~ ^([^@/: ]+/[^@/: ]+)$ ]] || fatal "upkg: Expected packagename ('user/pkg') not '%s'" "$3"
        upkg_uninstall_dep "$3" "$prefix/lib/upkg" "$prefix/bin"
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

upkg_root() (
  local sourcing_file=$1
  if [[ -n $sourcing_file ]]; then
    cd "$(dirname "$(realpath "${sourcing_file}")")"
  fi
  until [[ -e $PWD/upkg.json ]]; do
    if [[ $PWD = '/' ]]; then
      fatal 'upkg root: Unable to find package root (no upkg.json found in this or any parent directory)'
    fi
    cd ..
  done
  printf "%s\n" "$PWD"
)

upkg_parse_repospec() {
  if [[ $repospec =~ ^([^@/: ]+/[^@/: ]+)(@([^@ ]+))$ ]]; then
    printf "https://github.com/%s.git %s %s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"
  elif [[ $repospec =~ ([^@/: ]+/[^@/ ]+)(@([^@ ]+))$ ]]; then
    printf "%s %s %s\n" "${repospec%@*}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[3]}"
  else
    fatal "upkg: Unable to parse repospec '%s'. Expected a git cloneable URL followed by @version" "$repospec"
  fi
}

upkg_uninstall_dep() {
  local pkgname=$1 pkgspath=$2 binpath=$3
  local pkgpath="$pkgspath/$pkgname"
  # When upgrading remove old files & commands first
  local file command commands cmdpath
  if [[ ! -e "$pkgpath/upkg.json" ]]; then
    fatal "upkg: '%s' is not installed" "$pkgname"
  fi
  commands=$(jq -r '(.commands // {}) | to_entries[] | "\(.key)\n\(.value)"' <"$pkgpath/upkg.json")
  while [[ -n $commands ]] && read -r -d $'\n' command; do
    read -r -d $'\n' file
    cmdpath="$binpath/$command"
    if [[ -e $cmdpath && $(realpath "$cmdpath") = $pkgpath/* ]]; then
      rm "$cmdpath"
    fi
  done <<<"$commands"
  rm -rf "$pkgpath"
  if [[ -z $(find "$(dirname "$pkgpath")" -mindepth 1 -maxdepth 1) ]]; then
    rm -rf "$(dirname "$pkgpath")"
  fi
}

upkg_prepare_pkg() {
  local repospec=$1 pkgspath=$2 binpath=$3 tmppkgspath=$4 parsed_spec repourl pkgname pkgversion
  parsed_spec=$(upkg_parse_repospec "$repospec")
  read -r -d $'\n' repourl pkgname pkgversion <<<"$parsed_spec"
  local pkgpath="$pkgspath/$pkgname" tmppkgpath=$tmppkgspath/$pkgname
  if [[ -n "$pkgversion" ]]; then
    if ! out=$(git clone -q --depth=1 --branch="$pkgversion" "$repourl" "$tmppkgpath" 2>&1); then
      fatal "upkg: Unable to clone. Error:\n%s" "$out"
    fi
  else
    if ! out=$(git clone -q --depth=1 "$repourl" "$tmppkgpath" 2>&1); then
      fatal "upkg: Unable to clone. Error:\n%s" "$out"
    fi
  fi
  if ! jq empty < "$tmppkgpath/upkg.json"; then
    fatal "upkg: The package '%s' does not contain a valid upkg.json" "$pkgname"
  fi

  local file files command commands cmdpath
  files=$(jq -r '(["upkg.json"] + (.files // []) + [(.commands // {})[]] | unique)[]' <"$tmppkgpath/upkg.json")
  commands=$(jq -r '(.commands // {}) | to_entries[] | "\(.key)\n\(.value)"' <"$tmppkgpath/upkg.json")
  while [[ -n $files ]] && read -r -d $'\n' file; do
    if [[ $file =~ ^/ || $file =~ /\.\.(/|$) || $file =~ // || ! -f "$tmppkgpath/$file" ]]; then
      fatal "upkg: Error on file '%s' in package %s@%s.
All files in 'files' and 'commands' must:
* be relative
* not contain parent dir parts ('../')
* exist in the repository" "$file" "$pkgname" "$pkgversion"
    fi
  done <<<"$files"
  while [[ -n $commands ]] && read -r -d $'\n' command; do
    read -r -d $'\n' file
    if [[ ! -x "$tmppkgpath/$file" ]]; then
      fatal "upkg: Error on command '%s' in package %s@%s. The file '%s' does not exist or is not executable" "$command" "$file" "$pkgname" "$pkgversion"
    fi
    if [[ $command =~ (/| ) ]]; then
      fatal "upkg: Error on command '%s' in package %s@%s. The command may not contain spaces or slashes" "$command" "$pkgname" "$pkgversion"
    fi
    cmdpath="$binpath/$command"
    if [[ -e $cmdpath && $(realpath "$cmdpath") != $pkgpath/* ]]; then
      fatal "upkg: Error on command '%s' in package %s@%s. The symlink for it exists and does not point to the package" "$command" "$pkgname" "$pkgversion"
    fi
  done <<<"$commands"

  upkg_prepare_deps "$pkgpath" "$tmppkgspath/.upkg" "$tmppkgpath/upkg.json"
}

upkg_install_pkg() {
  local repospec=$1 pkgspath=$2 binpath=$3 tmppkgspath=$4 parsed_spec _repourl pkgname _pkgversion
  parsed_spec=$(upkg_parse_repospec "$repospec")
  read -r -d $'\n' _repourl pkgname _pkgversion <<<"$parsed_spec"
  local pkgpath="$pkgspath/$pkgname" tmppkgpath=$tmppkgspath/$pkgname

  if [[ -e "$pkgpath" ]]; then
    upkg_uninstall_dep "$pkgname" "$pkgspath" "$binpath"
  fi

  local file files command commands
  files=$(jq -r '(["upkg.json"] + (.files // []) + [(.commands // {})[]] | unique)[]' <"$tmppkgpath/upkg.json")
  commands=$(jq -r '(.commands // {}) | to_entries[] | "\(.key)\n\(.value)"' <"$tmppkgpath/upkg.json")
  while [[ -n $files ]] && read -r -d $'\n' file; do
    mkdir -p "$(dirname "$pkgpath/$file")"
    cp -a "$tmppkgpath/$file" "$pkgpath/$file"
  done <<<"$files"
  if [[ -n $commands ]]; then
    mkdir -p "$binpath"
    while [[ -n $commands ]] && read -r -d $'\n' command; do
      read -r -d $'\n' file
      ln -s "$pkgpath/$file" "$binpath/$command"
    done <<<"$commands"
  fi

  upkg_install_deps "$pkgpath" "$tmppkgspath/.upkg"
}

upkg_prepare_deps() {
  local pkgpath=$1 tmppkgspath=$2 tmpkupkgpath=$3 deps dep
  deps=$(jq -r '(.dependencies // []) | to_entries[] | "\(.key)@\(.value)"' <"$tmpkupkgpath")
  while [[ -n $deps ]] && read -r -d $'\n' dep; do
    upkg_prepare_pkg "$dep" "$pkgpath/.upkg" "$pkgpath/.upkg/.bin" "$tmppkgspath/.upkg" || fatal "upkg: Error while installing dependency '%s' for '%s'" "$dep"  "$pkgpath/upkg.json"
  done <<<"$deps"
}

upkg_install_deps() {
  local pkgpath=$1 tmppkgspath=$2 deps dep
  deps=$(jq -r '(.dependencies // []) | to_entries[] | "\(.key)@\(.value)"' <"$pkgpath/upkg.json")
  while [[ -n $deps ]] && read -r -d $'\n' dep; do
    upkg_install_pkg "$dep" "$pkgpath/.upkg" "$pkgpath/.upkg/.bin" "$tmppkgspath/.upkg" || fatal "upkg: Error while installing dependency '%s' for '%s'" "$dep" "$pkgpath/upkg.json"
  done <<<"$deps"
}

fatal() {
  local tpl=$1; shift
  # shellcheck disable=2059
  printf -- "$tpl\n" "$@" >&2
  exit 1
}

upkg "$@"
