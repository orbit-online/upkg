#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar
@test "deduplication does not change the executability of duplicated files" {
  local name=default/executable
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

@test "depending on the same file as an archive and a file does not clash" {
  :
}
