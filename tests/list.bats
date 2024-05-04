#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "global, dep installed" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package "$name"
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg list -g
  assert_snapshot_output acme-metadata-installed
}

@test "local, dep installed" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package "$name"
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg list
  assert_snapshot_output acme-metadata-installed
}

@test "local, no dep installed" {
  run -0 upkg list
  assert_snapshot_output
}
