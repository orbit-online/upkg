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
  assert_snapshot_output
  assert_snapshot_path
}

@test "local, filesystem, no metadata, tarball, rename" {
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar#acme-empty" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}

@test "local, filesystem, no metadata, git" {
  local name=acme-empty-v1.0.2-no-metadata
  create_git_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.git" "$GIT_COMMIT"
  assert_snapshot_output
  assert_snapshot_path
}

@test "local, filesystem, no metadata, git, rename" {
  local name=acme-empty-v1.0.2-no-metadata
  create_git_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.git#name=acme-empty" "$GIT_COMMIT"
  assert_snapshot_output
  assert_snapshot_path
}

@test "local, filesystem, metadata, tarball" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path local-metadata-tarball
}

@test "local, remote, metadata, tarball" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  serve_file "$PACKAGE_FIXTURES/$name.tar"
  run -0 upkg add http://localhost:8080/$name.tar "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path local-metadata-tarball
}

@test "global, remote, metadata, git" {
  run -0 upkg add -g https://github.com/orbit-online/records.sh 493ebb2c7c52dcf8f83a6fcaae6c7cbcfb2be736
  assert_snapshot_output
  assert_snapshot_path "" "$HOME/.local"
}

@test "global, remote, no metadata, tarball" {
  run -0 upkg add -g 'https://s3-eu-west-1.amazonaws.com/orbit-binaries/orbit-cli-v0.1.3.tar.gz?AWSAccessKeyId=AKIAZVIOIP7XN4CAKZNT&Expires=2028891302&Signature=03Zofm0v1BcNK%2Bd6RzIlTUwuRsQ%3D'
  assert_snapshot_output
  assert_snapshot_path "" "$HOME/.local"
}

@test "don't link non-executable files in bin/" {
  local name=no-executables shasum
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path "" "$HOME/.local"
}

@test "failing dependency causes nothing to be installed" {
  local name=failing-dependency
  create_tar_package $name
  run -1 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}

@test "adding same package with same name does nothing (checksum given)" {
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_path "same package, same name"
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path "same package, same name"
}

@test "adding same package does nothing (checksum not given)" {
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_path "same package, same name"
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar"
  assert_snapshot_output
  assert_snapshot_path "same package, same name"
}

@test "adding package with same name but different checksum fails (checksum given)" {
  local \
    name1=acme-empty-v1.0.2-metadata
    name2=duplicates/acme-empty-v1.0.2-metadata
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" "$TAR_SHASUM"
  assert_snapshot_path
  run -1 upkg add "$PACKAGE_FIXTURES/$name2.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}

@test "adding package with same name but different checksum fails (checksum not given)" {
  local \
    name1=acme-empty-v1.0.2-metadata
    name2=duplicates/acme-empty-v1.0.2-metadata
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" "$TAR_SHASUM"
  assert_snapshot_path
  create_tar_package $name2
  run -1 upkg add "$PACKAGE_FIXTURES/$name2.tar"
  assert_snapshot_output
  assert_snapshot_path
}

@test "adding same package with same checksum but different name succeeds" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar#alias=acme-empty-2" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path "$BATS_TEST_DESCRIPTION"
}

@test "adding two packages containing the same command fails" {
  local \
    name1=acme-empty-v1.0.2-metadata
    name2=acme-empty-v1.0.2-no-metadata
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" "$TAR_SHASUM"
  assert_snapshot_path
  create_tar_package $name2
  run -1 upkg add "$PACKAGE_FIXTURES/$name2.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}

@test ".upkg/.bin/ linked executable works" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  run -0 .upkg/.bin/acme-empty-v1.0.2.bin
}
