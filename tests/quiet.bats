#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "cannot use -v and -q at the same time" {
  run -1 upkg -qv add doesnotmatter
  assert_snapshot_output
}

# bats test_tags=http,git
@test "git http repo install with -q is quiet" {
  local name=default/acme
  create_git_package $name
  run -0 upkg add -q -t git -g $HTTPD_PKG_FIXTURES_ADDR/$name.git $GIT_COMMIT
  assert_output ""
}

# bats test_tags=ssh,git
@test "git ssh repo install with -q is quiet" {
  local name=default/acme
  create_git_package $name
  run -0 upkg add -q -t git -g package-fixtures:"$PACKAGE_FIXTURES/$name.git" $GIT_COMMIT
  assert_output ""
}

# bats test_tags=tar
@test "adding removing a package with -q is quiet" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add -q "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_output ""
  run -0 upkg remove -q acme
  assert_output ""
}


# bats test_tags=tar
@test "running upkg install is quiet" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add -q "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  rm -rf .upkg
  run -0 upkg install -q
  assert_output ""
}

@test "list -q only outputs table" {
  run --separate-stderr upkg -q list
  # shellcheck disable=SC2154
  assert_equal "$stderr" ""
}
