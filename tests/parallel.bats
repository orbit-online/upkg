#!/usr/bin/env bats

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

# bats test_tags=tar,file
@test "succesfully installs lots of deduplicating packages in parallel" {
  local name names=(
    default/acme
    default/acme-no-metadata
    default/no-executables
    default/scattered-executables
    "default/spaces in name"
    default/dep-1
    default/dep-2
    default/dep-3
    default/dep-4
    default/dep-5
  )
  for name in "${names[@]}"; do
    create_tar_package "$name"
  done
  create_file_package default/executable
  local archives=(1 2 3 4 5) i
  for i in "${archives[@]}"; do ln -s "$PACKAGE_FIXTURES/default/dep-$i.tar" "dep-$i.tar"; done
  create_tar_package default/dependomania
  UPKG_SEQUENTIAL=false run -0 upkg add "$PACKAGE_FIXTURES/default/dependomania.tar"
  for i in "${archives[@]}"; do rm "dep-$i.tar"; done
  mv .upkg/.packages/dependomania.tar@$TAR_SHASUM .upkg/.packages/dependomania.tar@STATIC
  ln -sf .packages/dependomania.tar@STATIC .upkg/dependomania
  assert_snapshot_path
  assert_all_links_valid
}
