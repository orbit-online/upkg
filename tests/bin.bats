#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "cannot use -B and -b at the same time" {
  local name=default/acme
  create_tar_package $name
  run -1 upkg add -b bin -B "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path shared/empty
}

# bats test_tags=tar
@test "bin property in upkg.json is read and causes all specified executables to be linked" {
  local name=default/scattered-executables
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
  assert_file_executable .upkg/.bin/another-tool
}

# bats test_tags=tar
@test "small -b is respected" {
  local name=default/scattered-executables
  create_tar_package $name
  run -0 upkg add -b bin/not-default-linked.sh "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "big -B is respected" {
  local name=default/scattered-executables
  create_tar_package $name
  run -0 upkg add -B "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=file
@test "-B is respected on files" {
  local name=default/executable
  create_file_package $name
  run -0 upkg add -B "$PACKAGE_FIXTURES/$name" $FILE_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=file
@test "executable file is linked and made executable" {
  local name=default/executable
  create_file_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name" $FILE_SHASUM
  assert_file_executable .upkg/executable
  assert_file_executable .upkg/.bin/executable
}

# bats test_tags=file
@test "non-executable file is linked and made executable" {
  local name=default/non-executable
  create_file_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name" $FILE_SHASUM
  assert_file_executable .upkg/non-executable
  assert_file_executable .upkg/.bin/non-executable
}

# bats test_tags=file
@test "-X is respected" {
  local name=default/executable
  create_file_package $name
  run -0 upkg add -X "$PACKAGE_FIXTURES/$name" $FILE_SHASUM
  assert_file_not_executable .upkg/executable
  assert_file_not_exists .upkg/.bin/executable
  assert_snapshot_path
}

# bats test_tags=tar
@test "cannot use -X on tar" {
  local name=default/acme
  create_tar_package $name
  run -1 upkg add -X "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
}

# bats test_tags=tar
@test "complains about missing binpath" {
  local name=default/scattered-executables
  create_tar_package $name
  run -0 upkg add -b non-existent "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
}

# bats test_tags=tar
@test "complains about non-executable binpath" {
  local name=default/scattered-executables
  create_tar_package $name
  run -0 upkg add -b tools/not-an-exec "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
}

# bats test_tags=tar
@test "-b can be specified multiple times" {
  local name=default/scattered-executables
  create_tar_package $name
  run -0 upkg add -b bin/not-default-linked.sh -b tools/tools-exec "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "bin can only specify paths in .upkg/" {
  local name=invalid/disallowed-binpaths
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "bin can symlink to .upkg/.bin and .upkg/pkgname" {
  create_tar_package default/scattered-executables
  local name=default/metapackage
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_file_executable .upkg/.bin/another-tool
  assert_file_executable .upkg/.bin/root-exec.sh
}

# bats test_tags=tar
@test "bin can symlink to dependencies part deux" {
  create_tar_package default/scattered-executables
  local name=default/crafty-binpaths
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_output
  assert_file_executable .upkg/.bin/another-tool2
  assert_file_executable .upkg/.bin/not-default-linked.sh
  assert_file_executable .upkg/.bin/to-other-pkg
  assert_file_executable .upkg/.bin/bin-exec.sh
}

# bats test_tags=tar
@test "handles commands with spaces" {
  local name=default/command-with-spaces
  create_tar_package $name
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_path "" "$HOME/.local"
  assert_file_executable "$HOME/.local/lib/upkg/.upkg/.bin/command with spaces.bin"
  assert_file_executable "$HOME/.local/bin/command with spaces.bin"
}

# bats test_tags=tar
@test "removes old commands" {
  local \
    name1=default/command-with-spaces
    name2=default/scattered-executables
  create_tar_package $name1
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  create_tar_package $name2
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  run -0 upkg remove -g command-with-spaces
  assert_snapshot_path "" "$HOME/.local"
}

# bats test_tags=tar
@test "removes old commands 2" {
  local \
    name1=default/command-with-spaces
    name2=default/scattered-executables
  create_tar_package $name1
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name1.tar" $TAR_SHASUM
  create_tar_package $name2
  run -0 upkg add -g "$PACKAGE_FIXTURES/$name2.tar" $TAR_SHASUM
  run -0 upkg remove -g scattered-executables
  assert_snapshot_path "" "$HOME/.local"
}
