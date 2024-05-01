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
  assert_snapshot
  assert_snapshot_files "" "$HOME/.local"
}

@test "metadata, global" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  run -0 upkg remove -g acme-empty
  assert_snapshot
  assert_snapshot_files "" "$HOME/.local"
}
