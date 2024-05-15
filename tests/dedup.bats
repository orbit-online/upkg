#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=file
@test "deduplication does not change the executability of duplicated files" {
  local name=default/executable
  create_file_package $name
  run -0 upkg add -p executable "$PACKAGE_FIXTURES/$name" $FILE_SHASUM
  run -0 upkg add -p not-executable -X "$PACKAGE_FIXTURES/$name" $FILE_SHASUM
  assert_file_executable .upkg/executable
  assert_file_not_executable .upkg/not-executable
}

# bats test_tags=tar
@test "deep dependencies work" {
  local archives=(1 2 3 4 5) i
  for i in "${archives[@]}"; do
    create_tar_package "default/dep-$i"
    ln -s "$PACKAGE_FIXTURES/default/dep-$i.tar" "dep-$i.tar"
  done
  run -0 upkg add "$PACKAGE_FIXTURES/default/dep-1.tar"
  for i in "${archives[@]}"; do
    rm "dep-$i.tar"
  done
  assert_snapshot_output
  assert_snapshot_path
}

# bats test_tags=tar
@test "depending on the same unnamed repo as an archive and a file does not clash" {
  local name=default/acme-no-metadata
  create_tar_package $name
  run -0 upkg add -p archive -t tar "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  run -0 upkg add -p file -t file "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  assert_snapshot_path
}

# bats test_tags=file
@test "deduping matching checksums does not clobber pkgnames" {
  create_file_package default/executable
  run -0 upkg add "$PACKAGE_FIXTURES/default/executable" $FILE_SHASUM
  create_file_package default/non-executable
  run -0 upkg add "$PACKAGE_FIXTURES/default/non-executable" $FILE_SHASUM
  assert_snapshot_path
}

# bats test_tags=tar
@test "dedup links to parent package are valid" {
  create_tar_package default/dep-5
  local name=default/triple-dep
  create_tar_package $name
  run -0 upkg add "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
  mv .upkg/.packages/triple-dep.tar@$TAR_SHASUM .upkg/.packages/triple-dep.tar@STATIC
  ln -sf .packages/triple-dep.tar@STATIC .upkg/triple-dep
  assert_snapshot_path
  assert_all_links_valid
}
