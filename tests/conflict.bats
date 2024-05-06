#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "adding same package with same options fails" {
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_path
  run -1 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "adding two packages containing the same command fails" {
  local \
    name1=default/acme \
    name2=default/acme-no-metadata
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  assert_snapshot_path shared/acme
  create_tar_package $name2
  run -1 upkg add "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path shared/acme
}

# bats test_tags=tar
@test "invalid pkgname rename to the existing pkgname results in conflict" {
  local \
    name1=disallowed/with-slash-in-name \
    name2=disallowed/with-newline-in-name
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  assert_snapshot_path
  create_tar_package $name2
  run -1 upkg add "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}
