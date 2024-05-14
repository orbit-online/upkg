#!/usr/bin/env bats
# bats file_tags=tar

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "test install package creation and installation" {
  (
    cd "$BATS_TEST_DIRNAME/.."
    run -0 upkg bundle -d "$HOME/upkg.tar.gz" -V testing bin lib upkg.schema.json README.md LICENSE
  )
  run -0 "$BATS_TEST_DIRNAME/../tools/create-install-snapshot.sh" "$HOME/upkg.tar.gz" upkg-install.tar.gz
  mkdir "$HOME/.local"
  tar -xf upkg-install.tar.gz -C "$HOME/.local"
  assert_snapshot_path "" "$HOME/.local"
}
