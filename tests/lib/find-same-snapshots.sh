#!/usr/bin/env bash
# shellcheck disable=2059,2064
set -Eeo pipefail
shopt -s inherit_errexit nullglob

PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/../..")

# Sets up a directory for upkg with only the barest of essentials and creates a upkg wrapper which overwrites PATH with it
main() {
  DOC="find-same-snapshots.sh - Find identical snapshots
Usage:
  find-same-snapshots.sh
"
  [[ $# -eq 0 ]] || { printf "%s\n" "$DOC"; return 1; }
  local test_file snapshot test_file_cmp snapshot_cmp
  cd "$PKGROOT/tests/snapshots"
  for test_file in *; do
    for snapshot in "$test_file"/*; do
      for test_file_cmp in *; do
        for snapshot_cmp in "$test_file_cmp"/*; do
          # Don't compare files we already compared the other way around
          [[ $snapshot < "$snapshot_cmp" ]] || continue
          ! diff -q "$snapshot" "$snapshot_cmp" >/dev/null || printf "%s and %s are the same\n" "$snapshot" "$snapshot_cmp"
        done
      done
    done
  done
}

main "$@"
