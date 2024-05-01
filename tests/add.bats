#!/usr/bin/env bats

load 'helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "local, filesystem, no metadata, tarball" {
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot
  assert_snapshot_files
}

@test "local, filesystem, no metadata, tarball, rename" {
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar#acme-empty" "$TAR_SHASUM"
  assert_snapshot
  assert_snapshot_files
}

@test "local, filesystem, no metadata, git" {
  local name=acme-empty-v1.0.2-no-metadata shasum
  create_git_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.git" "$GIT_COMMIT"
  assert_snapshot
  assert_snapshot_files
}

@test "local, filesystem, no metadata, git, rename" {
  local name=acme-empty-v1.0.2-no-metadata shasum
  create_git_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.git#name=acme-empty" "$GIT_COMMIT"
  assert_snapshot
  assert_snapshot_files
}

@test "local, filesystem, metadata, tarball" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot
  assert_snapshot_files local-metadata-tarball
}

@test "local, remote, metadata, tarball" {
  local name=acme-empty-v1.0.2-metadata shasum
  create_tar_package $name
  shasum=$TAR_SHASUM
  serve_file "$PACKAGE_FIXTURES/$name.tar"
  run -0 upkg add http://localhost:8080/$name.tar "$shasum"
  assert_snapshot
  assert_snapshot_files local-metadata-tarball
}

@test "global, remote, metadata, git" {
  run -0 upkg add -g https://github.com/orbit-online/records.sh 493ebb2c7c52dcf8f83a6fcaae6c7cbcfb2be736
  assert_snapshot
  assert_snapshot_files "" "$HOME/.local"
}

@test "global, remote, no metadata, tarball" {
  run -0 upkg add -g 'https://s3-eu-west-1.amazonaws.com/orbit-binaries/orbit-cli-v0.1.3.tar.gz?AWSAccessKeyId=AKIAZVIOIP7XN4CAKZNT&Expires=2028891302&Signature=03Zofm0v1BcNK%2Bd6RzIlTUwuRsQ%3D'
  assert_snapshot
  assert_snapshot_files "" "$HOME/.local"
}
