#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

# bats file_tags=shellcheck
@test 'shellcheck' {
  type shellcheck &>/dev/null || skip 'shellcheck not installed'
  shellcheck -x "$BATS_TEST_DIRNAME"/*.{bats,bash,sh} "$BATS_TEST_DIRNAME/../bin/upkg"
}
