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
  local name=default/acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "tarballs can be renamed" {
  local name=default/acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add -p acme-empty "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=git
@test "local git repo install from the filesystem with no metadata succeeds" {
  local name=default/acme-empty-v1.0.2-no-metadata
  create_git_package $name
  run -0 upkg add -t git "$PACKAGE_FIXTURES/$name.git" $GIT_COMMIT
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=git
@test "git repos can be renamed" {
  local name=default/acme-empty-v1.0.2-no-metadata
  create_git_package $name
  run -0 upkg add -t git -p acme-empty "$PACKAGE_FIXTURES/$name.git" $GIT_COMMIT
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "local tarball install with metadata has name from package" { # TODO: rename
  local name=default/acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path metadata-tarball
  assert_dir_exists .upkg/acme-empty
}

# bats test_tags=remote,tar
@test "remote tarball install with metadata has name from package" { # TODO: rename
  local name=default/acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add $HTTPD_PKG_FIXTURES_ADDR/$name.tar $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path metadata-tarball
  assert_dir_exists .upkg/acme-empty
}

# bats test_tags=remote,git
@test "remote git repo install succeeds" {
  local name=default/acme-empty-v1.0.2-metadata
  create_git_package $name
  run -0 upkg add -t git -g $HTTPD_PKG_FIXTURES_ADDR/$name.git $GIT_COMMIT
  assert_snapshot_output
  assert_snapshot_path "" "$HOME/.local"
}

# bats test_tags=tar,remote,wget
@test "failing dependency causes nothing to be installed" {
  local name=negative/failing-dependency
  create_tar_package $name
  run -1 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output "" "${output//Server: SimpleHTTP*}" # server response has version and date in the output, which changes, so remove that part
  assert_snapshot_path
}

# bats test_tags=tar
@test "adding same package with same options fails" {
  local name=default/acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_path "same package, same name"
  run -1 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path "same package, same name"
}

# bats test_tags=tar
@test "adding same package with same command but different pkgname succeeds" {
  local name=default/acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg add -p acme-empty-2 "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path "$BATS_TEST_DESCRIPTION"
}

# bats test_tags=tar
@test "adding two packages containing the same command fails" {
  local \
    name1=default/acme-empty-v1.0.2-metadata \
    name2=default/acme-empty-v1.0.2-no-metadata
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  assert_snapshot_path
  create_tar_package $name2
  run -1 upkg add "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}
