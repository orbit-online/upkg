#!/usr/bin/env bats

load 'helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "warns and then replaces when a package with a disallowed name in upkg.json is added" {
  local name=disallowed/with-at-in-name
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}

@test "silently replaces invalid characters in name when upkg.json does not exist" {
  local name=disallowed/with@in-name
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}

@test "allows name override to contain @" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar#name=has@in-name" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}

@test "warns and then replaces slashes in upkg.json package name" {
  local name=disallowed/with-slash-in-name
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}

@test "warns and then replaces slashes in name override" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar#name=has/in-name" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}

@test "warns and then replaces newlines in name override" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar#name=has"$'\n'"in-name" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}

@test "warns and then replaces when a package with a newline in upkg.json is added" {
  local name=disallowed/with-newline-in-name
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}
