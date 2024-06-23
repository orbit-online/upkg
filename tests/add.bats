#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "local tarball install from the filesystem with no metadata succeeds" {
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output shared/acme-no-metadata
  assert_snapshot_path shared/acme-no-metadata
  assert_file_executable .upkg/.bin/acme.bin
}

# bats test_tags=tar
@test "tarballs can be renamed" {
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add -p acme-2 "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output shared/acme-no-metadata
  assert_snapshot_path
}

# bats test_tags=git
@test "local git repo install from the filesystem with no metadata succeeds" {
  local name=default/acme-no-metadata
  create_git_package $name
  run -0 upkg add -t git "$PACKAGE_FIXTURES/$name.git" $GIT_COMMIT
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=git
@test "git repos can be renamed" {
  local name=default/acme-no-metadata
  create_git_package $name
  run -0 upkg add -t git -p acme-2 "$PACKAGE_FIXTURES/$name.git" $GIT_COMMIT
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "local tarball install with pkgname from package" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output shared/acme
  assert_snapshot_path shared/acme
  assert_dir_exists .upkg/acme
}

# bats test_tags=http,tar
@test "tarball install via http with pkgname from package" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$HTTPD_PKG_FIXTURES_ADDR/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path shared/acme
  assert_dir_exists .upkg/acme
}

# bats test_tags=http,git
@test "git repo install via http succeeds" {
  local name=default/acme
  create_git_package $name
  run -0 upkg add -t git -g "$HTTPD_PKG_FIXTURES_ADDR/$name.git" $GIT_COMMIT
  assert_snapshot_output
  assert_snapshot_path acme-git-global "$HOME/.local"
}

# bats test_tags=ssh,git
@test "git repo install via ssh succeeds" {
  local name=default/acme
  create_git_package $name
  run -0 upkg add -t git -g package-fixtures:"$PACKAGE_FIXTURES/$name.git" $GIT_COMMIT
  assert_snapshot_output
  assert_snapshot_path acme-git-global "$HOME/.local"
}

# bats test_tags=tar
@test "adding same package with same command but different pkgname succeeds" {
  local name=default/acme
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg add -p acme-2 "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_path
}

# bats test_tags=tar
@test "upkg.json controls pkgname" {
  local name=default/acme-renamed
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
  assert_dir_exists .upkg/acme-renamed
}

# bats test_tags=tar
@test "can add relative paths globally" {
  local name=default/acme-renamed
  create_tar_package $name
  cp "$PACKAGE_FIXTURES/$name.tar" "$(basename $name).tar"
  run -0 upkg add -g "$(basename $name).tar" $TAR_SHASUM
  assert_snapshot_output
}

# bats test_tags=file,tar
@test "can depend on upkg.json" {
  create_tar_package default/scattered-executables
  create_file_package default/executable
  local name=default/metapackage.upkg.json
  create_file_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name" $FILE_SHASUM
  assert_file_executable "$HOME/.local/bin/bin-exec.sh"
  assert_file_executable "$HOME/.local/bin/executable"
  mv "$HOME/.local/lib/upkg/.upkg/.packages/metapackage.upkg.json@$FILE_SHASUM" "$HOME/.local/lib/upkg/.upkg/.packages/metapackage.upkg.json@STATIC"
  ln -sf .packages/metapackage.upkg.json@STATIC "$HOME/.local/lib/upkg/.upkg/metapackage"
  ln -sf ../.packages/metapackage.upkg.json@STATIC/.upkg/.bin/bin-exec.sh "$HOME/.local/lib/upkg/.upkg/.bin/bin-exec.sh"
  ln -sf ../.packages/metapackage.upkg.json@STATIC/.upkg/.bin/executable "$HOME/.local/lib/upkg/.upkg/.bin/executable"
  assert_snapshot_path "" "$HOME/.local"
}

# bats test_tags=file,tar,http
@test "can depend on remote upkg.json" {
  create_tar_package default/scattered-executables
  create_file_package default/executable
  local name=default/metapackage.upkg.json
  create_file_package $name
  run -0 upkg add -g "$HTTPD_PKG_FIXTURES_ADDR/$name" $FILE_SHASUM
  assert_snapshot_output
  assert_file_executable "$HOME/.local/bin/bin-exec.sh"
  assert_file_executable "$HOME/.local/bin/executable"
}

# bats test_tags=file,tar
@test ".upkg.json is removed from pkgname" {
  create_tar_package default/scattered-executables
  create_file_package default/executable
  local name=default/metapackage-noname.upkg.json
  create_file_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name" $FILE_SHASUM
  assert_link_exists .upkg/metapackage-noname
}

# bats test_tags=zip
@test "can install zip packages" {
  local name=default/acme
  create_zip_package $name
  run -0 upkg add --pkgtype zip "$PACKAGE_FIXTURES/$name.zip" $ZIP_SHASUM
  assert_snapshot_output
  assert_file_executable .upkg/.bin/acme.bin
}
