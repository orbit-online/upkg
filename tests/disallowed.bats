#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "does not replace @ slashes in upkg.json pkgname" {
  local name=disallowed/with-at-in-name
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
  assert_all_links_valid
}

# bats test_tags=tar
@test "does not replace @ in generated pkgname when upkg.json does not exist" {
  local name=disallowed/with@in-name
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
  assert_all_links_valid
}

# bats test_tags=tar
@test "silently replaces slashes in upkg.json pkgname" {
  local name=disallowed/with-slash-in-name
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
  assert_all_links_valid
}

# bats test_tags=tar
@test "silently replaces slashes in name override" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add -p has/in-name "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output shared/acme
  assert_snapshot_path
  assert_all_links_valid
}

# bats test_tags=tar
@test "silently replaces newlines in name override" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add -p has$'\n'in-name "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output shared/acme
  assert_snapshot_path
  assert_all_links_valid
}

# bats test_tags=tar
@test "silently replaces newlines in upkg.json pkgname" {
  local name=disallowed/with-newline-in-name
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
  assert_all_links_valid
}
