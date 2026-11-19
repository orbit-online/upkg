#!/usr/bin/env bats
# bats file_tags=no-upkg

load 'lib/helpers'
setup_file() { common_setup_file; }
setup() { common_setup; }
teardown() { common_teardown; }
teardown_file() { common_teardown_file; }

@test "_ln_sT creates a symlink and does not replace an existing one" {
  run -0 _ln_sT target-a link
  assert_link_exists link
  assert_equal "$(readlink link)" target-a
  run _ln_sT target-b link
  assert_equal "$(readlink link)" target-a
}

@test "_ln_sTf replaces an existing symlink" {
  run -0 _ln_sT target-a link
  run -0 _ln_sTf target-b link
  assert_equal "$(readlink link)" target-b
}

@test "_ln_sTf replaces a symlink to a directory instead of linking inside it" {
  mkdir dir-a dir-b
  run -0 _ln_sT dir-a link
  run -0 _ln_sTf dir-b link
  assert_equal "$(readlink link)" dir-b
  assert_not_exist dir-a/dir-b
}
