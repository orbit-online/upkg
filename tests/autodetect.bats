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
