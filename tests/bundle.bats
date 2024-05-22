#!/usr/bin/env bats
# bats file_tags=bundle,tar

# shellcheck source=lib/shellcheck-defs.sh
source "$BATS_TEST_DIRNAME/lib/empty-file.sh"

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "upkg can bundle itself" {
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

@test "bin path is default included when no path is specified" {
  cp -r "$PACKAGE_TEMPLATES/default/acme"/* .
  run -0 upkg bundle -d acme.tar.gz -V v1.0.2
  mkdir acme
  tar -xf acme.tar.gz -C acme
  assert_snapshot_path "" acme
}

@test "fails when there is nothing to bundle" {
  cp -r "$PACKAGE_TEMPLATES/default/acme/upkg.json" .
  run -1 upkg bundle -d acme.tar.gz -V v1.0.2
  assert_snapshot_output
}

@test "bundles everything specified in bin property" {
  cp -r "$PACKAGE_TEMPLATES/default/scattered-executables"/* .
  run -0 upkg bundle -d scattered-executables.tar.gz -V v0.0.1
  mkdir scattered-executables
  tar -xf scattered-executables.tar.gz -C scattered-executables
  assert_snapshot_path "" scattered-executables
  assert_snapshot_output
}

@test "fails when paths specified in bin do not exist" {
  cp -r "$PACKAGE_TEMPLATES/default/scattered-executables/upkg.json" .
  run -1 upkg bundle -d scattered-executables.tar.gz -V v0.0.1
  assert_snapshot_output "" "$(grep -v 'Option --mtime' <<<"$output")"
}

@test "fails when specified paths do not exist" {
  cp -r "$PACKAGE_TEMPLATES/default/acme/upkg.json" .
  run -1 upkg bundle -d acme.tar.gz -V v1.0.2 non-existent
  assert_snapshot_output "" "$(grep -v 'Option --mtime' <<<"$output")"
}

@test "can bundle without upkg.json" {
  cp -r "$PACKAGE_TEMPLATES/default/acme"/* .
  rm upkg.json
  run -0 upkg bundle -V v1.0.2
  tar xOf package.tar.gz upkg.json | jq -re '. | if has("name") then false else true end'
  assert_snapshot_output
}

@test "can override pkgname in bundle" {
  cp -r "$PACKAGE_TEMPLATES/default/acme"/* .
  rm upkg.json
  run -0 upkg bundle -p acme-overridden -V v1.0.2
  tar xOf acme-overridden.tar.gz upkg.json | jq -re '.name=="acme-overridden"'
  assert_snapshot_output
}

@test "bundle falls back to package.tar.gz" {
  cp -r "$PACKAGE_TEMPLATES/default/acme"/* .
  rm upkg.json
  run -0 upkg bundle -d acme.tar.gz -V v1.0.2
  assert_snapshot_output
}

@test "bundle version is optional" {
  cp -r "$PACKAGE_TEMPLATES/default/acme"/* .
  run -0 upkg bundle
  tar xOf acme.tar.gz upkg.json | jq -re '.version=="v1.0.2"'
  assert_snapshot_output
}

@test "bundle version is not set if unspecified" {
  cp -r "$PACKAGE_TEMPLATES/default/acme-no-metadata"/* .
  run -0 upkg bundle
  tar xOf package.tar.gz upkg.json | jq -re '. | if has("version") then false else true end'
}
