#!/usr/bin/env bash
# shellcheck disable=2059,2064
set -Eeo pipefail
shopt -s inherit_errexit nullglob

# Sets up a directory for upkg with only the barest of essentials and creates a upkg wrapper which overwrites PATH with it
main() {
  DOC="setup-upkg-path-wrapper.sh - Restrict upkg to the bare minimum of commands
Usage:
  setup-upkg-path-wrapper.sh <upkg-path> <restricted-basepath> [<bash-path>]

This script will create two directories:
  <restricted-basepath>/restricted-bin/:
    A directory with the bare minimum of commands needed for upkg to run.
  <restricted-basepath>/upkg-wrapper-bin/:
    A directory containing only the executable upkg wrapper script that sets
    \$PATH to <restricted-basepath>/restricted-bin/ and invokes upkg and
    forwards all arguments. Prepend this directory to \$PATH in order to invoke
    the wrapper script when running upkg.
"
  [[ $# -ge 2 && $# -le 3 && $1 != -h && $1 != --help ]] || { printf "%s\n" "$DOC"; return 1; }

  local upkg_path=$1 basepath=$2 bash_path=$3

  # shellcheck disable=SC2154
  local \
    upkg_wrapper_bin=$basepath/upkg-wrapper-bin \
    restricted_bin=$basepath/restricted-bin
  mkdir -p "$upkg_wrapper_bin" "$restricted_bin"
  # shellcheck disable=SC2016,SC2154
  printf '#/usr/bin/env bash
PATH="${RESTRICTED_BIN:-"%s"}" "%s" "$@"
' "$restricted_bin" "$upkg_path" >"$upkg_wrapper_bin/upkg"
  chmod +x "$upkg_wrapper_bin/upkg"

  local cmd target required_commands=(
    jq
    uname # os/arch selection commands
    basename dirname sort comm cut grep # string commands
    mv cp mkdir touch rm ln chmod cat readlink realpath # fs commands
    sleep flock # concurrency commands
    git tar # archive commands
  ) optional_commands=(
    wget curl ssh column sha256sum shasum zip unzip gtar
    bzip2 xz lzip lzma lzop gzip compress zstd # tar compressions
  )
  if [[ -n $bash_path ]]; then
    [[ -x $bash_path ]] || { printf "Unable to find required command '%s'\n" "$bash_path" >&2; return 1; }
    ln -s "$bash_path" "$restricted_bin/bash"
  else
    required_commands+=(bash)
  fi
  for cmd in "${required_commands[@]}"; do
    target=$(which "$cmd") || { printf "Unable to find required command '%s'\n" "$cmd" >&2; return 1; }
    ln -s "$target" "$restricted_bin/$cmd"
  done
  for cmd in "${optional_commands[@]}"; do
    target=$(which "$cmd") || { printf "Unable to find optional command '%s'\n" "$cmd" >&2; continue; }
    ln -s "$target" "$restricted_bin/$cmd"
  done
  if [[ ! -e $restricted_bin/sha256sum && ! -e $restricted_bin/shasum ]]; then
    fatal "Unable to find sha256sum or shasum"
  fi
  if [[ ! -e $restricted_bin/wget && ! -e $restricted_bin/curl ]]; then
    fatal "Unable to find wget or curl"
  fi
  ln -s "../upkg-wrapper-bin/upkg" "$restricted_bin/upkg"
}

main "$@"
