#!/usr/bin/env bats

load 'helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "uses wget when curl is not available" {
  type wget &>/dev/null || skip 'wget is not available'
  remove_commands wget
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
}

@test "falls back to curl when wget is not available" {
  type curl &>/dev/null || fail 'curl is not available'
  remove_commands curl
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
}

@test "fails when installing a remote repo and wget & curl are not available" {
  remove_commands curl wget
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  serve_dir
  run -1 upkg add http://localhost:8080/$name.tar
  assert_snapshot_output
}

@test "git is not needed when installing tarball" {
  remove_commands git
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
}

@test "fails when installing a tarball but tar is not available" {
  remove_commands tar
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -1 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
}

@test "tar is not needed when installing git repo" {
  remove_commands tar
  local name=acme-empty-v1.0.2-no-metadata
  create_git_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.git" "$GIT_COMMIT"
}

@test "fails when installing a git repo but git is not available" {
  remove_commands git
  local name=acme-empty-v1.0.2-no-metadata
  create_git_package $name
  run -1 upkg add "$PACKAGE_FIXTURES/$name.git" "$GIT_COMMIT"
}

@test "tar and git are not needed when installing a plain file" {
  remove_commands git
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
}

@test "wget and curl are not needed when installing a local repo" {
  remove_commands wget curl
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
}

@test "wget can perform head request" {
  type wget &>/dev/null || skip 'wget is not available'
  remove_commands curl
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  serve_dir
  run -0 upkg add http://localhost:8080/$name.tar
  assert_snapshot_output
  assert_snapshot_path
}

@test "curl can perform head request" {
  type curl &>/dev/null || fail 'curl is not available'
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  serve_dir
  run -0 upkg add http://localhost:8080/$name.tar
  assert_snapshot_output
  assert_snapshot_path
}
