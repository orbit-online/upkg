#!/usr/bin/env bats

load '/usr/lib/bats/bats-support/load'
load '/usr/lib/bats/bats-assert/load'

: "${UPKG_PATH?"Must specificy path to upkg binary."}"

setup_file() {
  bats_require_minimum_version 1.5.0
}

setup() {
  export upkg=$UPKG_PATH
  export UPKG_SEQUENTIAL=true
  export LOCAL_TEST_DIR="$BATS_TEST_DIRNAME/tests/${BATS_TEST_DESCRIPTION// /-}"
  mkdir -p "$BATS_TEST_TMPDIR/home/" "$BATS_TEST_TMPDIR/workdir/"
  cd "$BATS_TEST_TMPDIR/workdir/" || fail 'PANIC! Could not change directory to test context directory' || return 1
  [[ -d "$LOCAL_TEST_DIR/fixtures-local" ]] && cp -ax "$LOCAL_TEST_DIR/fixtures-local/." "$BATS_TEST_TMPDIR/workdir/"
  [[ -d "$LOCAL_TEST_DIR/fixtures-global" ]] && cp -ax "$LOCAL_TEST_DIR/fixtures-global/." "$BATS_TEST_TMPDIR/home/.local/"
  export HOME="$BATS_TEST_TMPDIR/home" # manipulate where "global" points to. $HOME/.local
}

serve_file() {
  nc -l 8080 < <(printf -- 'HTTP/1.1 200 OK\r\nDate: %s\r\nContent-Length: %d\r\n\r\n' "$(date -R)" "$(stat --format='%s' "$1")"; cat "$1") &>/dev/null
}

fail() {
  local tpl=$1; shift
  # shellcheck disable=SC2059
  printf -- "fail $tpl\n" "$@" >&2
  return 1
}

assert_stdout() {
  [[ $output == "$1" ]] || \
  fail 'stdout:\n%s\n' "$(diff --color=always --label=actual --label=expected -su <(echo "$output") <(echo "$1"))"
}

assert_stderr() {
  [[ $stderr == "$1" ]] || \
  fail 'stderr:\n%s\n' "$(diff --color=always --label=actual --label=expected -su <(echo "$stderr") <(echo "$1"))"
}

assert_stdout_file() {
  expected_stdout=$(cat "$LOCAL_TEST_DIR/stdout" 2>/dev/null || printf -- '')
  [[ $expected_stdout != '*' ]] || return 0
  assert_stdout "$expected_stdout"
}

assert_stderr_file() {
  expected_stderr=$(cat "$LOCAL_TEST_DIR/stderr" 2>/dev/null || printf -- '')
  [[ $expected_stderr != '*' ]] || return 0
  assert_stderr "$expected_stderr"
}

assert_global_result_directory() {
  actual_result=$(cd $HOME/.local/ && tree -a "." -I '.gitignore')
  expected_result=$(cd "$LOCAL_TEST_DIR/result-global" && tree -a -I '.gitignore')
  [[ $actual_result == "$expected_result" ]] || fail 'tree global:\n%s\n' "$(diff --color=always --label=actual --label=expected -su <(echo "$actual_result") <(echo "$expected_result"))"
}

assert_local_result_directory() {
  actual_result=$(cd $BATS_TEST_TMPDIR/workdir/ && tree -a "." -I '.gitignore')
  expected_result=$(cd "$LOCAL_TEST_DIR/result-local" && tree -a -I '.gitignore')
  [[ $actual_result == "$expected_result" ]] || fail 'tree local:\n%s\n' "$(diff --color=always --label=actual --label=expected -su <(echo "$actual_result") <(echo "$expected_result"))"
}

# @test "install global git longoption" {
#   run --separate-stderr $upkg install -g "file://$BATS_TEST_DIRNAME/assets/acme-empty.git@v1.0.2"
#   assert_stderr_file
#   assert_global_result_directory
#   [[ $status == 0 ]]
# }

@test "no arguments" {
  run --separate-stderr $upkg
  assert_stderr_file
  [[ $status == 1 ]]
}

# @test "help command" {
#   run --separate-stderr $upkg help
#   assert_stdout_file
#   [[ $status == 0 ]]
# }

@test "help longoption" {
  run --separate-stderr $upkg --help
  assert_stdout_file
  [[ $status == 0 ]]
}

@test "help shorthand" {
  run --separate-stderr $upkg -h
  assert_stdout_file
  [[ $status == 0 ]]
}

@test "list global dep installed" {
  run --separate-stderr $upkg list -g
  assert_stdout_file
  [[ $status == 0 ]]
}

@test "list global non upkg root" {
  run --separate-stderr $upkg list -g
  [[ $status == 0 ]]
}

@test "list local dep installed" {
  run --separate-stderr $upkg list
  assert_stdout_file
  [[ $status == 0 ]]
}

@test "list local dep not installed" {
  run --separate-stderr $upkg list
  assert_stdout_file
  [[ $status == 0 ]]
}

@test "list local non upkg root" {
  run --separate-stderr $upkg list
  [[ $status == 0 ]]
}

@test "install global git long" {
  run --separate-stderr $upkg add -g https://github.com/orbit-online/bitwarden-tools 5d6f72cf7a8dab416902f92d53e84781548def61
  assert_stderr_file
  assert_global_result_directory
  [[ $status == 0 ]]
}

# @test "install global git shorthand" {
#   run --separate-stderr $upkg install -g orbit-online/upkg@v0.14.0
#   assert_stderr_file
#   assert_global_result_directory
#   [[ $status == 0 ]]
# }

@test "install global tarball no metadata" {
  run --separate-stderr $upkg install -g 'https://s3-eu-west-1.amazonaws.com/orbit-binaries/orbit-cli-v0.1.3.tar.gz?AWSAccessKeyId=AKIAZVIOIP7XN4CAKZNT&Expires=2028891302&Signature=03Zofm0v1BcNK%2Bd6RzIlTUwuRsQ%3D@1d04b2b7e0d9edbb611bff4ea032de6d5dc98ccc77be6e7d1b51c175da299511'
  assert_stderr_file
  assert_global_result_directory
  [[ $status == 0 ]]
}

@test "install local tarball name metadata" {
  run --separate-stderr $upkg install
  assert_stderr_file
  assert_local_result_directory
  [[ $status == 0 ]]
}

@test "install local tarball no metadata" {
  run --separate-stderr $upkg install
  assert_stderr_file
  assert_local_result_directory
  [[ $status == 0 ]]
}

@test "install local tarball serve" {
  (serve_file "$BATS_TEST_DIRNAME/assets/acme-empty-v1.0.2.tar.gz") &
  run --separate-stderr $upkg install
  wait
  assert_stderr_file
  assert_local_result_directory
  [[ $status == 0 ]]
}

@test "install local tarball version metadata" {
  run --separate-stderr $upkg install
  assert_stderr_file
  assert_local_result_directory
  [[ $status == 0 ]]
}

@test "uninstall global" {
  run --separate-stderr $upkg uninstall -g orbit-online/upkg
  assert_stderr_file
  [[ $status == 0 ]]
}
