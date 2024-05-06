#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "cannot use -B and -b at the same time" {
  local name=default/acme
  create_tar_package $name
  run -1 upkg add -b bin -B "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path shared/empty
}

# bats test_tags=tar
@test "bin property in upkg.json is read and causes all specified executables to be linked" {
  local name=default/scattered-executables
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "-b is respected" {
  local name=default/scattered-executables
  create_tar_package $name
  run -0 upkg add -b bin/not-default-linked.sh "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "-B is respected" {
  local name=default/scattered-executables
  create_tar_package $name
  run -0 upkg add -B "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}
