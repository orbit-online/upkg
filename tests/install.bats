#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "writability check fails on non-writable .packages" {
  mkdir -p ".upkg/.packages"
  chmod ug-w ".upkg/.packages"
  local name=default/acme
  create_tar_package $name
  run -1 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  chmod ug+w ".upkg/.packages"
}

# bats test_tags=tar
@test "writability check fails on non-writable install prefix" {
  mkdir -p "$HOME/.local/lib"
  chmod ug-w "$HOME/.local"
  local name=default/acme
  create_tar_package $name
  run -1 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  chmod ug+w "$HOME/.local"
}

# bats test_tags=tar
@test "writability check fails on non-writable global bin" {
  mkdir -p "$HOME/.local/bin"
  chmod ug-w "$HOME/.local/bin"
  local name=default/acme
  create_tar_package $name
  run -1 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  chmod ug+w "$HOME/.local/bin"
}
