#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "local tarball install from the filesystem with no metadata succeeds" {
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output shared/acme-no-metadata
  assert_snapshot_path shared/acme-no-metadata
  assert_file_executable .upkg/.bin/acme.bin
}

# bats test_tags=tar
@test "tarballs can be renamed" {
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add -p acme-2 "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output shared/acme-no-metadata
  assert_snapshot_path
}

# bats test_tags=git
@test "local git repo install from the filesystem with no metadata succeeds" {
  local name=default/acme-no-metadata
  create_git_package $name
  run -0 upkg add -t git "$PACKAGE_FIXTURES/$name.git" $GIT_COMMIT
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=git
@test "git repos can be renamed" {
  local name=default/acme-no-metadata
  create_git_package $name
  run -0 upkg add -t git -p acme-2 "$PACKAGE_FIXTURES/$name.git" $GIT_COMMIT
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "local tarball install with pkgname from package" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output shared/acme
  assert_snapshot_path shared/acme
  assert_dir_exists .upkg/acme
}

# bats test_tags=http,tar
@test "tarball install via http with pkgname from package" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add $HTTPD_PKG_FIXTURES_ADDR/$name.tar $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path shared/acme
  assert_dir_exists .upkg/acme
}

# bats test_tags=http,git
@test "git repo install via http succeeds" {
  local name=default/acme
  create_git_package $name
  run -0 upkg add -t git -g $HTTPD_PKG_FIXTURES_ADDR/$name.git $GIT_COMMIT
  assert_snapshot_output
  assert_snapshot_path "" "$HOME/.local"
}

# bats test_tags=ssh,git
@test "git repo install via ssh succeeds" {
  local name=default/acme
  create_git_package $name
  run -0 upkg add -t git -g package-fixtures:"$PACKAGE_FIXTURES/$name.git" $GIT_COMMIT
  assert_snapshot_output
  assert_snapshot_path "" "$HOME/.local"
}

# bats test_tags=tar
@test "adding same package with same command but different pkgname succeeds" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg add -p acme-2 "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "upkg.json controls pkgname" {
  local name=default/acme-renamed
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
  assert_dir_exists .upkg/acme
}
