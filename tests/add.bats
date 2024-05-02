#!/usr/bin/env bats

load 'helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "local tarball install from the filesystem with no metadata succeeds" {
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}

@test "tarballs can be aliased" {
  local name=acme-empty-v1.0.2-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar#alias=acme-empty" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path
}

@test "local git repo install from the filesystem with no metadata succeeds" {
  local name=acme-empty-v1.0.2-no-metadata
  create_git_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.git" "$GIT_COMMIT"
  assert_snapshot_output
  assert_snapshot_path
}

@test "git repos can be aliased" {
  local name=acme-empty-v1.0.2-no-metadata
  create_git_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.git#alias=acme-empty" "$GIT_COMMIT"
  assert_snapshot_output
  assert_snapshot_path
}

@test "local tarball install with metadata has name from package" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path metadata-tarball
  assert_dir_exists .upkg/acme-empty
}

@test "remote tarball install with metadata has name from package" {
  local name=acme-empty-v1.0.2-metadata
  create_tar_package $name
  run -0 upkg add http://localhost:8080/$name.tar "$TAR_SHASUM"
  assert_snapshot_output
  assert_snapshot_path metadata-tarball
  assert_dir_exists .upkg/acme-empty
}

@test "remote git repo install succeeds" {
  local name=acme-empty-v1.0.2-metadata
  create_git_package $name
  run -0 upkg add -g http://localhost:8080/$name.git "$GIT_COMMIT"
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
