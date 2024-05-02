#!/usr/bin/env bats

load 'helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test ".upkg/.bin/ linked executable works" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  run -0 .upkg/.bin/acme-empty-v1.0.2.bin
}

@test ".local/.bin/ linked executable works" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  run -0 "$HOME/.local/bin/acme-empty-v1.0.2.bin"
}

@test "don't link non-executable files in bin/" {
  local name=no-executables
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path "" "$HOME/.local"
}

@test "conflicting global commands are detected and no change happens" {
  mkdir -p "$HOME/.local/bin"
  touch "$HOME/.local/bin/acme-empty-v1.0.2.bin"
  chmod +x "$HOME/.local/bin/acme-empty-v1.0.2.bin"
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -1 upkg add -g "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path "" "$HOME/.local"
}
