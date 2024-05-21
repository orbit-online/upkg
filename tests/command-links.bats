#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test ".upkg/.bin/ linked executable works" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 .upkg/.bin/acme.bin
}

# bats test_tags=tar
@test ".local/.bin/ linked executable works" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 "$HOME/.local/bin/acme.bin"
}

# bats test_tags=tar
@test "don't link non-executable files in bin/" {
  local name=default/no-executables
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path "" "$HOME/.local"
}

# bats test_tags=tar
@test "conflicting global commands are detected and no change happens" {
  mkdir -p "$HOME/.local/bin"
  touch "$HOME/.local/bin/acme.bin"
  chmod +x "$HOME/.local/bin/acme.bin"
  local name=default/acme
  create_tar_package $name
  run -1 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path "" "$HOME/.local"
}

# bats test_tags=tar
@test "command linking does not fail when encountering non symlinks in bin/" {
  local name=default/acme
  create_tar_package $name
  mkdir -p "$HOME/.local/bin"
  touch "$HOME/.local/bin/000"
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg add -fg "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_path "" "$HOME/.local"
}
