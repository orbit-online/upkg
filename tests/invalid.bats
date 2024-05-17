#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "refuses to install from packages with existing .upkg/ in root" {
  local name=invalid/with-existing-upkg
  create_tar_package $name
  run -1 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path shared/empty
}

# bats test_tags=tar
@test "fails on tar add with invalid sha256" {
  local name=default/acme
  create_tar_package $name
  run -1 upkg add "$PACKAGE_FIXTURES/$name.tar" abcdef
  assert_output "upkg: A sha256 checksum must be 64 hexchars"
  assert_snapshot_path shared/empty
}

# bats test_tags=git
@test "fails on git add with invalid sha1" {
  local name=default/acme
  create_git_package $name
  run -1 upkg add "$PACKAGE_FIXTURES/$name.git" abcdef
  assert_output "upkg: A git sha1 commit hash must be 40 hexchars"
  assert_snapshot_path shared/empty
}

# bats test_tags=git
@test "fails install without upkg.json" {
  run -1 upkg install
  assert_snapshot_output
  assert_snapshot_path shared/empty
}

# bats test_tags=git
@test "fails on git add with non-existent repo" {
  run -1 upkg add "$PACKAGE_FIXTURES/non-existent.git" 0123456789abcdef0123456789abcdef01234567
  assert_snapshot_output
  assert_snapshot_path shared/empty
}

# bats test_tags=git
@test "fails on git add with non-existent sha1" {
  local name=default/acme
  create_git_package $name
  run -1 upkg add "$PACKAGE_FIXTURES/$name.git" 0123456789abcdef0123456789abcdef01234567
  assert_output --partial "Unable to checkout '0123456789abcdef0123456789abcdef01234567'"
  assert_snapshot_path shared/empty
}

# bats test_tags=http,tar,wget
@test "failing dependency causes nothing to be installed" {
  local name=invalid/failing-dependency
  create_tar_package $name
  run -1 upkg add "$HTTPD_PKG_FIXTURES_ADDR/$name.tar" $TAR_SHASUM
  assert_snapshot_output "" "${output//Server: SimpleHTTP*}" # server response has version and date in the output, which changes, so remove that part
  assert_snapshot_path shared/empty
}

# bats test_tags=http,tar,wget
@test "fails on tar add with non-existent repo" {
  run -1 upkg add "$HTTPD_PKG_FIXTURES_ADDR/non-existent.tar" 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  assert_snapshot_output "" "${output//Server: SimpleHTTP*}"
  assert_snapshot_path shared/empty
}
