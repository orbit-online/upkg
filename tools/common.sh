#!/usr/bin/env bash
# shellcheck source-path=..

setup_reproducible_tar() {
  # Ensure stable file sorting
  export LC_ALL=C
  # Don't include atime & ctime in tar archives (https://reproducible-builds.org/docs/archives/)
  unset POSIXLY_CORRECT
  # Fixed timestamp for reproducible builds. 2024-01-01T00:00:00Z
  export SOURCE_DATE_EPOCH=1704067200
}

fatal() {
  local tpl=$1; shift
  printf -- "%s: $tpl\n" "$(basename "${BASH_SOURCE[0]}")" "$@" >&2
  return 1
}
