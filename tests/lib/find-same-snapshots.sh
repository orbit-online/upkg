#!/usr/bin/env bash
# shellcheck source-path=../..
# shellcheck disable=2059,2064
set -Eeo pipefail
shopt -s inherit_errexit nullglob

PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")
source "$PKGROOT/lib/compat.sh"

# Sets up a directory for upkg with only the barest of essentials and creates a upkg wrapper which overwrites PATH with it
main() {
  DOC="find-same-snapshots.sh - Find identical snapshots
Usage:
  find-same-snapshots.sh
"
  [[ $# -eq 0 ]] || { printf "%s\n" "$DOC"; return 1; }
  local test_file snapshot test_file_cmp snapshot_cmp sha
  declare -A same
  cd "$PKGROOT/tests/snapshots"
  for test_file in *; do
    for snapshot in "$test_file"/*; do
      for test_file_cmp in *; do
        for snapshot_cmp in "$test_file_cmp"/*; do
          # Don't compare files we already compared the other way around
          [[ $snapshot < "$snapshot_cmp" ]] || continue
          if diff -q "$snapshot" "$snapshot_cmp" >/dev/null; then
            sha=$(sha256 "$snapshot")
            same[$sha]="${same[$sha]}\n  $snapshot\n  $snapshot_cmp"
          fi
        done
      done
    done
  done
  for i in "${!same[@]}"; do
    printf "These files are the same:${same[$i]}\n\n"
  done
}

main "$@"
