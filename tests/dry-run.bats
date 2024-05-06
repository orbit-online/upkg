#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "add does not have --dry-run" {
  local name=default/acme
  create_tar_package $name
  run -1 upkg add -n "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output shared/usage
  assert_snapshot_path shared/empty
}

@test "remove does not have --dry-run" {
  run -1 upkg remove -n acme
  assert_snapshot_output shared/usage
  assert_snapshot_path shared/empty
}
