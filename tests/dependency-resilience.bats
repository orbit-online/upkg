#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar,wget
@test "uses wget when curl is not available" {
  remove_commands wget
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
}

# bats test_tags=tar,curl
@test "falls back to curl when wget is not available" {
  remove_commands curl
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
}

# bats test_tags=http,tar
@test "fails when installing a remote repo and wget & curl are not available" {
  remove_commands curl wget
  local name=default/acme
  create_tar_package $name
  run -1 upkg add "$HTTPD_PKG_FIXTURES_ADDR/$name.tar"
  assert_snapshot_output
}

# bats test_tags=tar
@test "git is not needed when installing tarball" {
  remove_commands git
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
}

# bats test_tags=tar
@test "fails when installing a tarball but tar is not available" {
  remove_commands tar
  local name=default/acme-no-metadata
  create_tar_package $name
  run -1 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
}

# bats test_tags=git
@test "tar is not needed when installing git repo" {
  remove_commands tar
  local name=default/acme-no-metadata
  create_git_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.git" $GIT_COMMIT
}

# bats test_tags=git
@test "fails when installing a git repo but git is not available" {
  remove_commands git
  local name=default/acme-no-metadata
  create_git_package $name
  run -1 upkg add "$PACKAGE_FIXTURES/$name.git" $GIT_COMMIT
}

# bats test_tags=tar
@test "tar and git are not needed when installing a plain file" {
  remove_commands git
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
}

# bats test_tags=tar
@test "wget and curl are not needed when installing a local repo" {
  remove_commands wget curl
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
}

# bats test_tags=http,tar
@test "wget can perform head request" {
  type wget &>/dev/null || skip 'wget is not available'
  remove_commands curl
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$HTTPD_PKG_FIXTURES_ADDR/$name.tar"
  assert_snapshot_output download-acme
  assert_snapshot_path shared/acme
}

# bats test_tags=http,tar
@test "curl can perform head request" {
  type curl &>/dev/null || fail 'curl is not available'
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$HTTPD_PKG_FIXTURES_ADDR/$name.tar"
  assert_snapshot_output download-acme
  assert_snapshot_path shared/acme
}

# bats test_tags=jq
@test "fails when jq is not available" {
  remove_commands jq
  run -1 upkg list
  assert_snapshot_output
}
