#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# @test "add" {
#   local name=acme-no-metadata
#   create_tar_package $name
#   run -0 upkg add -n "$PACKAGE_FIXTURES/$name.tar" $TAR_SHASUM
#   assert_snapshot_output
#   assert_snapshot_path
# }
