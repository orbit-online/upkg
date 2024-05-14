#!/usr/bin/env bats
# bats file_tags=packaging,no-upkg,tar

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "test upkg package creation" {
  "$BATS_TEST_DIRNAME/../tools/create-package.sh" testing upkg.tar.gz "$BATS_TEST_DIRNAME/.."
  mkdir upkg
  tar -xf upkg.tar.gz -C upkg
  assert_snapshot_path "" upkg
}

@test "test install package creation" {
  "$BATS_TEST_DIRNAME/../tools/create-package.sh" testing upkg.tar.gz "$BATS_TEST_DIRNAME/.."
  "$BATS_TEST_DIRNAME/../tools/create-install-snapshot.sh" upkg.tar.gz upkg-install.tar.gz
  mkdir "$HOME/.local"
  tar -xf upkg-install.tar.gz -C "$HOME/.local"
  assert_snapshot_path "" "$HOME/.local"
}
