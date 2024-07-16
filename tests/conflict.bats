#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "adding same package with same options fails" {
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_path
  run -1 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "adding two packages containing the same command fails" {
  local \
    name1=default/acme \
    name2=default/acme-no-metadata
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  assert_snapshot_path shared/acme
  create_tar_package $name2
  run -1 upkg add "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path shared/acme
}

# bats test_tags=tar
@test "invalid pkgname rename to the existing pkgname results in conflict" {
  local \
    name1=disallowed/with-slash-in-name \
    name2=disallowed/with-newline-in-name
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  assert_snapshot_path
  create_tar_package $name2
  run -1 upkg add "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "adding package with conflicting alias fails" {
  local \
    name1=default/acme \
    name2=default/dep-5
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  assert_snapshot_path
  create_tar_package $name2
  run -1 upkg add -p acme "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "force operates normally on no conflict" {
  local \
    name1=default/acme
    name2=default/dep-5
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  create_tar_package $name2
  run -0 upkg add -f "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  assert_snapshot_output
}

# bats test_tags=tar
@test "force replaces existing package" {
  local \
    name1=default/acme
    name2=default/dep-5
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  create_tar_package $name2
  run -0 upkg add -p acme -f "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "force operates normally when replacing with same package" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg add -f "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "force fails when .upkg/ symlinks are not in sync" {
  local \
    name1=default/acme
    name2=default/dep-5
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  upkgjson=$(cat upkg.json)
  jq 'del(.dependencies[0])' <<<"$upkgjson" >upkg.json
  create_tar_package $name2
  run -1 upkg add -fp acme "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "force fails when upkg.json is not in sync" {
  local \
    name1=default/acme
    name2=default/dep-5
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  rm .upkg/acme
  create_tar_package $name2
  run -1 upkg add -fp acme "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  assert_snapshot_output
}

# bats test_tags=tar
@test "can force add to empty dir" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add -f "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "can force add to empty global dir" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add -gf "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "can force replace with local archive" {
  local \
    name1=default/acme old_shasum \
    name2=default/acme-v2
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  assert_dir_exists .upkg/.packages/acme.tar@$TAR_SHASUM
  old_shasum=$TAR_SHASUM
  create_tar_package $name2
  cp "$PACKAGE_FIXTURES/$name2.tar" acme.tar
  run -0 upkg add -f acme.tar $TAR_SHASUM
  assert_dir_not_exists .upkg/.packages/acme.tar@$old_shasum
  assert_dir_exists .upkg/.packages/acme.tar@$TAR_SHASUM
  assert_snapshot_output
}

# bats test_tags=tar,http
@test "can force replace with remote archive" {
  local \
    name1=default/acme old_shasum \
    name2=default/acme-v2
  create_tar_package $name1
  run -0 upkg add "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  assert_dir_exists .upkg/.packages/acme.tar@$TAR_SHASUM
  old_shasum=$TAR_SHASUM
  create_tar_package $name2
  run -0 upkg add -f "$HTTPD_PKG_FIXTURES_ADDR/$name2.tar" $TAR_SHASUM
  assert_dir_not_exists .upkg/.packages/acme.tar@$old_shasum
  assert_dir_exists .upkg/.packages/acme.tar@$TAR_SHASUM
  assert_snapshot_output
}

# bats test_tags=tar,zip
@test "can force replace tar with zip" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_dir_exists .upkg/.packages/acme.tar@$TAR_SHASUM
  create_zip_package $name
  run -0 upkg add -f "$PACKAGE_FIXTURES/$name.zip" $ZIP_SHASUM
  assert_dir_not_exists .upkg/.packages/acme.tar@$TAR_SHASUM
  assert_dir_exists .upkg/.packages/acme.zip@$ZIP_SHASUM
  assert_snapshot_output
}

# bats test_tags=file
@test "same package with different archs do not conflict" {
  local name=default/executable
  create_file_package $name
  # shellcheck disable=SC2030
  export UPKG_OS_ARCH=Linux/x86_64
  run -0 upkg add -u "$PACKAGE_FIXTURES/$name" $FILE_SHASUM
  export UPKG_OS_ARCH=Linux/arm64
  run -0 upkg add -u "$PACKAGE_FIXTURES/$name" $FILE_SHASUM
  assert_file_executable .upkg/.bin/executable
  assert_snapshot_output "os-arch-no-conflict.upkg.json" "$(cat upkg.json)"
}

# bats test_tags=file
@test "conflicting archs are detected" {
  local name=default/executable
  create_file_package $name
  # shellcheck disable=SC2031
  export UPKG_OS_ARCH=Linux/x86_64
  run -0 upkg add -u "$PACKAGE_FIXTURES/$name" $FILE_SHASUM
  export UPKG_OS_ARCH=Linux/REPLACEME
  run -0 upkg add -u "$PACKAGE_FIXTURES/$name" $FILE_SHASUM
  sed -i 's/REPLACEME/\*/g' upkg.json
  assert_snapshot_output "os-arch-conflict.upkg.json" "$(cat upkg.json)"
  rm -rf .upkg
  export UPKG_OS_ARCH=Linux/x86_64
  run -1 upkg install
  assert_snapshot_output
}
