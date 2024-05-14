#!/usr/bin/env bats
# bats file_tags=bundle,tar

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "test upkg bundling itself" {
  cp -r \
    "$BATS_TEST_DIRNAME/../bin" \
    "$BATS_TEST_DIRNAME/../lib" \
    "$BATS_TEST_DIRNAME/../upkg.json" \
    "$BATS_TEST_DIRNAME/../upkg.schema.json" \
    "$BATS_TEST_DIRNAME/../README.md" \
    "$BATS_TEST_DIRNAME/../LICENSE" \
    .
  run -0 upkg bundle -d "$HOME/upkg.tar.gz" -V testing bin lib upkg.schema.json README.md LICENSE
  mkdir upkg
  tar -xf "$HOME/upkg.tar.gz" -C upkg
  assert_snapshot_path "" upkg
}
