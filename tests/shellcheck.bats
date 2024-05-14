#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit
# bats file_tags=shellcheck,no-upkg

@test 'shellcheck upkg' {
  [[ -z $SKIP_SHELLCHECK ]] || skip "$SKIP_SHELLCHECK"
  shellcheck -x "$BATS_TEST_DIRNAME/../bin/upkg"
}

@test 'shellcheck tests' {
  [[ -z $SKIP_SHELLCHECK ]] || skip "$SKIP_SHELLCHECK"
  (
    cd tests
    shellcheck -x -- *.bats
    shellcheck -x -- lib/helpers.bash lib/setup-upkg-path-wrapper.sh
  )
}

@test 'shellcheck tools' {
  [[ -z $SKIP_SHELLCHECK ]] || skip "$SKIP_SHELLCHECK"
  shellcheck -x -- tools/*
}
