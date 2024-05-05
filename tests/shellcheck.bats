#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

# bats file_tags=shellcheck
@test 'shellcheck upkg' {
  type shellcheck &>/dev/null || skip 'shellcheck not installed'
  shellcheck -x "$BATS_TEST_DIRNAME/../bin/upkg"
}

# bats file_tags=shellcheck
@test 'shellcheck tests' {
  type shellcheck &>/dev/null || skip 'shellcheck not installed'
  (
    cd tests
    shellcheck -x -- *.bats
    shellcheck -x -- lib/helpers.bash lib/setup-upkg-path-wrapper.sh
  )
}
