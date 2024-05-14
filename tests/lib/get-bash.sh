#!/usr/bin/env bash
# shellcheck disable=2059,2064
set -Eeo pipefail
shopt -s inherit_errexit nullglob

PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")


main() {
  DOC="get-bash.sh - Download and compile a bash version
Usage:
  get-bash.sh <version>
"
  [[ $# -eq 1 && $1 != -h && $1 != --help ]] || { printf "%s\n" "$DOC"; return 1; }

  local versions=$PKGROOT/tests/assets/bash-versions
  mkdir -p "$versions"

  local version=$1
  local bash_dir=$versions/bash-$version
  local executable=$bash_dir/bash
  if [[ ! -x "$executable" ]]; then
    local archive=$versions/bash-$version.tar.gz
    [[ -e $archive ]] || wget -qO"$archive" "http://ftp.gnu.org/gnu/bash/bash-$version.tar.gz" >&2
    [[ -d $bash_dir ]] || tar -xf "$archive" -C "$versions" >&2
    [[ -e $bash_dir/Makefile ]] || (cd "$bash_dir"; exec ./configure >&2)
    (cd "$bash_dir"; exec make >&2)
  fi
  printf "%s\n" "$executable"
}

main "$@"
