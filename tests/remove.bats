#!/usr/bin/env bats

load 'helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "no metadata, global" {
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  run -0 upkg remove -g $name.tar
  assert_snapshot_output
  assert_snapshot_path "" "$HOME/.local"
}

@test "metadata, global" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  run -0 upkg remove -g acme-empty
  assert_snapshot_output
  assert_snapshot_path "" "$HOME/.local"
}

@test "add 1 -> add 2 -> remove 1" {
  local name1=acme-empty-v1.0.2-metadata name2=no-executables
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" "$TAR_SHASUM"
  create_tar_package $name2
  run -0 upkg add "$PACKAGE_FIXTURES/$name2.tar" "$TAR_SHASUM"
  run -0 upkg remove acme-empty
  assert_snapshot_output
  assert_snapshot_path
}
