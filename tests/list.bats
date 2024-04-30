#!/usr/bin/env bats

load 'helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "global, dep installed" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package "$name"
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  run -0 upkg list -g
  assert_output_file
}

@test "local, dep installed" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package "$name"
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  run -0 upkg list
  assert_output_file
}

@test "local, no dep installed" {
  run -0 upkg list
  assert_output_file
}
