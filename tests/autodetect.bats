#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=ssh,git
@test "can autodetect git repo via commit" {
  local name=default/acme
  create_git_package $name
  run -0 upkg add package-fixtures:"$PACKAGE_FIXTURES/$name.git" $GIT_COMMIT
  # Output is too unique to snapshot
  assert_equal "$(wc -l "$SSHD_PKG_FIXTURES_LOG")" "3 $SSHD_PKG_FIXTURES_LOG" # should only have log lines from the clone
  assert_snapshot_path shared/acme-git
}

# bats test_tags=ssh,git
@test "can autodetect git repo via ls-remote" {
  local name=default/acme
  create_git_package $name
  run -0 upkg add package-fixtures:"$PACKAGE_FIXTURES/$name.git"
  # Output is too unique to snapshot
  assert_equal "$(wc -l "$SSHD_PKG_FIXTURES_LOG")" "9 $SSHD_PKG_FIXTURES_LOG" # ls-remote causes more log lines
  assert_snapshot_path shared/acme-git
}

# bats test_tags=tar
@test "does not fail when .tar extension missing" {
  local name=default/acme
  create_tar_package $name $name.nottar
  run -0 upkg add -t tar "$PACKAGE_FIXTURES/$name.nottar"
  assert_snapshot_output nottar
  assert_snapshot_path shared/acme
}

# bats test_tags=tar,gz
@test "does not fail when .tar.gz extension missing" {
  local name=default/acme
  create_tar_package $name $name.nottar .gz
  run -0 upkg add -t tar "$PACKAGE_FIXTURES/$name.nottar"
  assert_snapshot_output nottar
  assert_snapshot_path
}

# bats test_tags=tar,bz2
@test "does not fail when .tar.bzip2 extension missing" {
  local name=default/acme
  create_tar_package $name $name.nottar .bz2
  run -0 upkg add -t tar "$PACKAGE_FIXTURES/$name.nottar"
  assert_snapshot_output nottar
  assert_snapshot_path
}

# bats test_tags=tar,bzip2
@test "archive added as -t file is not extracted" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add -t file "$PACKAGE_FIXTURES/$name.tar"
  assert_snapshot_path
}

# bats test_tags=tar,bzip2
@test "autodetects tar from extension" {
  local name=default/acme
  create_tar_package $name "" .bzip2
  run -0 upkg add -v "$PACKAGE_FIXTURES/$name.tar.bzip2"
  assert_snapshot_output
  assert_snapshot_path shared/acme
}
