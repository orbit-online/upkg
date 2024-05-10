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
  run -0 upkg remove -g "$(basename "$name")"
  assert_snapshot_output
  assert_snapshot_path shared/clean-global "$HOME/.local"
}

# bats test_tags=tar
@test "metadata, global" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg remove -g acme
  assert_snapshot_output
  assert_snapshot_path shared/clean-global "$HOME/.local"
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

# bats test_tags=tar
@test "succeeds in removing non-existent global package when lib/upkg does not exist" {
  run -0 upkg remove -g non-existent
  assert_snapshot_output non-existent-not-installed
}

# bats test_tags=tar
@test "succeeds in removing non-existent package when upkg.json and .upkg do not exist" {
  run -0 upkg remove non-existent
  assert_snapshot_output non-existent-not-installed
}

# bats test_tags=tar
@test "succeeds in removing non-existent package when upkg.json is in sync with .upkg" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg remove non-existent
  assert_snapshot_output non-existent-not-installed
}

# bats test_tags=tar
@test "succeeds in removing non-existent global package when lib/upkg/upkg.json is in sync with .upkg" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg remove -g non-existent
  assert_snapshot_output non-existent-not-installed
}

# bats test_tags=tar
@test "fails removing non-existent local package when upkg.json is not in sync with .upkg" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  upkgjson=$(cat upkg.json)
  jq 'del(.dependencies[0])' <<<"$upkgjson" >upkg.json
  run -1 upkg remove non-existent
  assert_snapshot_output non-existent-not-in-sync
}

# bats test_tags=tar
@test "fails removing non-existent global package when lib/upkg/upkg.json is not in sync with .upkg" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  upkgjson=$(cat "$HOME/.local/lib/upkg/upkg.json")
  jq 'del(.dependencies[0])' <<<"$upkgjson" >"$HOME/.local/lib/upkg/upkg.json"
  run -1 upkg remove -g non-existent
  assert_snapshot_output non-existent-not-in-sync
}

# bats test_tags=tar
@test "remove handles name overrides" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg add -p emca "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg remove emca
  assert_snapshot_output
  assert_snapshot_path
  assert_dir_exists .upkg/acme
  assert_dir_not_exists .upkg/emca
}

# bats test_tags=tar
@test "remove handles derived names" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg add -p emca "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg remove acme
  assert_snapshot_output
  assert_snapshot_path
  assert_dir_not_exists .upkg/acme
  assert_dir_exists .upkg/emca
}
