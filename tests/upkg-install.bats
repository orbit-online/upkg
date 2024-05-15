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
  cp -r \
    "$BATS_TEST_DIRNAME/../bin" \
    "$BATS_TEST_DIRNAME/../lib" \
    "$BATS_TEST_DIRNAME/../upkg.json" \
    "$BATS_TEST_DIRNAME/../upkg.schema.json" \
    "$BATS_TEST_DIRNAME/../README.md" \
    "$BATS_TEST_DIRNAME/../LICENSE" \
    .
  run -0 upkg bundle -d "$HOME/upkg.tar.gz" -V testing bin lib upkg.schema.json README.md LICENSE
  run -0 "$BATS_TEST_DIRNAME/../tools/create-install-snapshot.sh" "$HOME/upkg.tar.gz" upkg-install.tar.gz
  mkdir "$HOME/.local"
  tar -xf upkg-install.tar.gz -C "$HOME/.local"
  assert_all_links_valid "$HOME/.local"
  # Links validated, fix the ones with changing shasums before checking snapshot
  ln -sf "../.packages/upkg.tar@STATIC" "$HOME/.local/lib/upkg/.upkg/.bin/upkg"
  ln -sf ".packages/upkg.tar@STATIC" "$HOME/.local/lib/upkg/.upkg/upkg"
  mv "$HOME/.local/lib/upkg/.upkg/.packages"/upkg.tar@* "$HOME/.local/lib/upkg/.upkg/.packages/upkg.tar@STATIC"
  assert_snapshot_path "" "$HOME/.local"
}

@test "test compat install package creation and installation" {
  cp -r \
    "$BATS_TEST_DIRNAME/../bin" \
    "$BATS_TEST_DIRNAME/../lib" \
    "$BATS_TEST_DIRNAME/../upkg.json" \
    "$BATS_TEST_DIRNAME/../upkg.schema.json" \
    "$BATS_TEST_DIRNAME/../README.md" \
    "$BATS_TEST_DIRNAME/../LICENSE" \
    .
  run -0 upkg bundle -d "$HOME/upkg.tar.gz" -V testing bin lib upkg.schema.json README.md LICENSE
  run -0 "$BATS_TEST_DIRNAME/../tools/create-compat-install-snapshot.sh" "$HOME/upkg.tar.gz" upkg-compat.tar.gz upkg-compat-install.tar.gz
  mkdir upkg
  tar -xf upkg-compat.tar.gz -C upkg
  assert_all_links_valid upkg
  assert_snapshot_path compat-bundle upkg

  mkdir "$HOME/.local"
  tar -xf upkg-compat-install.tar.gz -C "$HOME/.local"
  assert_all_links_valid "$HOME/.local"
  # Links validated, fix the ones with changing shasums before checking snapshot
  ln -sf ../.packages/upkg-compat.tar@STATIC "$HOME/.local/lib/upkg/.upkg/.bin/upkg"
  ln -sf .packages/upkg-compat.tar@STATIC "$HOME/.local/lib/upkg/.upkg/upkg-compat"
  ln -sf .packages/upkg-compat.tar@STATIC "$HOME/.local/lib/upkg/.upkg/upkg-compat"
  mv "$HOME/.local/lib/upkg/.upkg/.packages"/upkg-compat.tar@* "$HOME/.local/lib/upkg/.upkg/.packages/upkg-compat.tar@STATIC"
  mv "$HOME/.local/lib/upkg/.upkg/.packages"/upkg.tar@* "$HOME/.local/lib/upkg/.upkg/.packages/upkg.tar@STATIC"
  ln -sf ../../upkg.tar@STATIC "$HOME/.local/lib/upkg/.upkg/.packages/upkg-compat.tar@STATIC/.upkg/upkg-new"
  assert_snapshot_path compat-install "$HOME/.local"
}
