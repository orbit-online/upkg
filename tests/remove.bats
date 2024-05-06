#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "no metadata, global" {
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg remove -g "$(basename "$name").tar"
  assert_snapshot_output
  assert_snapshot_path "shared/clean-global" "$HOME/.local"
}

# bats test_tags=tar
@test "metadata, global" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg remove -g acme
  assert_snapshot_output
  assert_snapshot_path "shared/clean-global" "$HOME/.local"
}

# bats test_tags=tar
@test "add 1 -> add 2 -> remove 1" {
  local name1=default/acme name2=default/no-executables
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  create_tar_package $name2
  run -0 upkg add "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  run -0 upkg remove acme
  assert_snapshot_output
  assert_snapshot_path
}
