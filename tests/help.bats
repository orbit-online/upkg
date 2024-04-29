#!/usr/bin/env bats

load 'helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "no arguments" {
  run -1 upkg
  assert_output_file help
}

@test "help longoption" {
  run -0 upkg --help
  assert_output_file help
}

@test "help shorthand" {
  run -0 upkg -h
  assert_output_file help
}

@test "invalid command" {
  run -1 upkg invalid-command
  assert_output_file help
}
