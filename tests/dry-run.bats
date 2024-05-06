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

@test "install with empty upkg.json and no .upkg/" {
  echo '{}' >upkg.json
  run -0 upkg install -n
  assert_snapshot_output shared/up-to-date
  assert_snapshot_path shared/upkg-json
}

# bats test_tags=tar
@test "install with populated upkg.json and populated .upkg/" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output shared/acme
  assert_snapshot_path shared/acme
  run -0 upkg install -n
  assert_snapshot_output shared/up-to-date
  assert_snapshot_path shared/acme
}

# bats test_tags=tar
@test "install with empty upkg.json and populated .upkg/" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output shared/acme
  assert_snapshot_path shared/acme
  echo '{}' >upkg.json
  run -1 upkg install -n
  assert_snapshot_output
  assert_snapshot_path shared/acme
}

# bats test_tags=tar
@test "install with populated upkg.json and no .upkg/" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output shared/acme
  assert_snapshot_path shared/acme
  rm -rf .upkg
  run -1 upkg install -n
  assert_snapshot_output
  assert_snapshot_path shared/upkg-json
}
