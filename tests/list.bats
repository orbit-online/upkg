#!/usr/bin/env bats
# bats file_tags=list

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "global, dep installed" {
  local name=default/acme
  create_tar_package "$name"
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg list -g
  assert_snapshot_output acme-metadata-installed
}

# bats test_tags=tar
@test "local, dep installed" {
  local name=default/acme
  create_tar_package "$name"
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg list
  assert_snapshot_output acme-metadata-installed
}

# bats test_tags=tar
@test "local, dep installed, json" {
  local name=default/acme
  create_tar_package "$name"
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg list -J
  assert_snapshot_output acme-metadata-installed-json
}

# bats test_tags=tar
@test "columnopts work" {
  local name=default/acme
  create_tar_package "$name"
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg list -- -J
  if [[ $(column --version) != *2.36.1 ]]; then
    # version 2.36.1 (and maybe before, used in debian bullseye) outputs the json formatted differently
    assert_snapshot_output column-json
  fi
}

# bats test_tags=tar
@test "columnopts deprecated" {
  local name=default/acme
  create_tar_package "$name"
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg list -J
  assert_snapshot_output column-deprecated
}

@test "local, no dep installed" {
  run -0 upkg list
  assert_snapshot_output empty
}
