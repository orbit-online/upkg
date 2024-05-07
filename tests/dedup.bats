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
