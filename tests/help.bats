#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "no arguments" {
  # TODO: Docopt cuts the help text wrong because of the μ multibyte char in pkg
  run -1 upkg
  assert_snapshot_output short-help
}

@test "help longoption" {
  run -0 upkg --help
  assert_snapshot_output long-help
}

@test "help shorthand" {
  run -0 upkg -h
  assert_snapshot_output long-help
}

@test "invalid command" {
  run -1 upkg invalid-command
  assert_snapshot_output short-help
}
