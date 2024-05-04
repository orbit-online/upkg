#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

common_setup_file() {
  export SNAPSHOTS
  SNAPSHOTS=$BATS_TEST_DIRNAME/snapshots/$(basename "$BATS_TEST_FILENAME" .bats)
}

common_setup() {
  if has_tag remote; then
    [[ -z $SKIP_REMOTE ]] || skip "$SKIP_REMOTE"
  else
    unset REMOTE_ADDR
  fi
  ! has_tag tar || [[ -z $SKIP_TAR ]] || skip "$SKIP_TAR"
  ! has_tag git || [[ -z $SKIP_GIT ]] || skip "$SKIP_GIT"
  export \
    HOME=$BATS_TEST_TMPDIR/home \
    GLOBAL_INSTALL_PREFIX=$BATS_TEST_TMPDIR/usr \
    PROJECT_ROOT=$BATS_TEST_TMPDIR/project
  # EUID cannot be set, so even when running as root make sure to install to $HOME
  export INSTALL_PREFIX=$HOME/.local
  # Don't let upkg run installs in parallel, this results in non-deterministic ouput
  export UPKG_SEQUENTIAL=true
  mkdir "$HOME" "$GLOBAL_INSTALL_PREFIX" "$PROJECT_ROOT"
  cd "$PROJECT_ROOT"
}

common_teardown() {
  if [[ -n $(jobs -p) ]]; then
    fail "There were unterminated background jobs after test completion"
  fi
  if has_tag remote; then
    # Output and clear server log after every test
    printf -- "-- webserver logs --\n" >&2
    cat "$REMOTE_LOG" >&2
    true >"$REMOTE_LOG"
  fi
}

common_teardown_file() {
  :
}

remove_commands() {
  cp -r "$RESTRICTED_BIN" "$BATS_TEST_TMPDIR/restricted-bin"
  local cmd
  for cmd in "$@"; do
    # Don't fail if the command doesn't exist in the first place (e.g. optional dependency)
    rm -f "$BATS_TEST_TMPDIR/restricted-bin/$cmd"
  done
  RESTRICTED_BIN="$BATS_TEST_TMPDIR/restricted-bin"
}

create_tar_package() {
  has_tag tar || fail "create_tar_package is used, but the test is not tagged with 'tar'"
  local tpl=$PACKAGE_TEMPLATES/$1 dest=$PACKAGE_FIXTURES/$1.tar
  mkdir -p "$(dirname "$dest")"
  # https://reproducible-builds.org/docs/archives/
  [[ -e "$dest" ]] || tar \
    --sort=name \
    --mtime="@${SOURCE_DATE_EPOCH}" \
    --owner=0 --group=0 --numeric-owner \
    -cf "$dest" -C "$tpl" .
  # shellcheck disable=SC2034
  TAR_SHASUM=$(shasum -a 256 "$dest" | cut -d' ' -f1)
}

create_git_package() {
  has_tag git || fail "create_git_package is used, but the test is not tagged with 'git'"
  local tpl=$PACKAGE_TEMPLATES/$1 working_copy=$PACKAGE_FIXTURES/$1.git-tmp dest=$PACKAGE_FIXTURES/$1.git
  mkdir -p "$(dirname "$dest")"
  if [[ ! -e $dest ]]; then
    mkdir "$working_copy"
    git init -q  "$working_copy"
    cp -r "$tpl/." "$working_copy/"
    git -C "$working_copy" add -A
    git -C "$working_copy" commit -q --no-gpg-sign -m 'Initial import'
    git clone --bare "$working_copy" "$dest"
    git -C "$dest" --bare update-server-info
  fi
  # shellcheck disable=SC2034
  GIT_COMMIT=$(git -C "$dest" rev-parse HEAD)
}

assert_equals_diff() {
  local expected=${1:-} actual=${2:-} out
  # Preserving trailing newlines is super cumbersome, let's hope we don't need it
  if ! out=$(diff --label=expected --label=actual -su <(printf -- "%s\n" "$expected") <(printf -- "%s\n" "$actual") | $DELTA); then
    printf -- "-- output differs --\n%s\n" "${out#$'\n'}" | fail
  fi
}

assert_snapshot_output() {
  local snapshot_name=${1:-$BATS_TEST_DESCRIPTION} actual=${2:-$output}
  snapshot_name=${snapshot_name//'/'/_}
  local snapshot_path=$SNAPSHOTS/$snapshot_name.out
  if [[ ! -e "$snapshot_path" ]]; then
    if ${CREATE_SNAPSHOTS:-false}; then
      mkdir -p "$SNAPSHOTS"
      # shellcheck disable=SC2001
      replace_values <<<"$output" > "$snapshot_path"
    else
      fail "The snapshot '${snapshot_path%"$SNAPSHOTS"}' does not exist, run with CREATE_SNAPSHOTS=true to create it"
    fi
  elif ${UPDATE_SNAPSHOTS:-false}; then
    # shellcheck disable=SC2001
    replace_values <<<"$output" > "$snapshot_path"
  fi
  assert_equals_diff "$(replace_vars "$snapshot_path")" "$actual"
}

assert_snapshot_path() {
  local snapshot_name=${1:-$BATS_TEST_DESCRIPTION} actual_path=$2
  snapshot_name=${snapshot_name//'/'/_}
  local snapshot_path=$SNAPSHOTS/$snapshot_name.files
  if [[ ! -e "$snapshot_path" ]]; then
    if ${CREATE_SNAPSHOTS:-false}; then
      mkdir -p "$SNAPSHOTS"
      get_file_structure "$actual_path" > "$snapshot_path"
    else
      fail "The snapshot '${snapshot_path%"$SNAPSHOTS"}' does not exist, run with CREATE_SNAPSHOTS=true to create it"
    fi
  elif ${UPDATE_SNAPSHOTS:-false}; then
    get_file_structure "$actual_path" > "$snapshot_path"
  fi
  assert_equals_diff "$(cat "$snapshot_path")" "$(get_file_structure "$actual_path")"
}

# shellcheck disable=SC2120
replace_values() {
  (if [[ -n $1 ]]; then cat "$1"; else cat; fi) | \
  sed "s#$BATS_TEST_TMPDIR#\$BATS_TEST_TMPDIR#g" | \
  sed "s#$BATS_RUN_TMPDIR#\$BATS_RUN_TMPDIR#g" | \
  (if [[ -n $REMOTE_ADDR ]]; then sed "s#$REMOTE_ADDR#\$REMOTE_ADDR#g"; else cat; fi)
}

# shellcheck disable=SC2120
replace_vars() {
  (if [[ -n $1 ]]; then cat "$1"; else cat; fi) | \
  sed "s#\$BATS_TEST_TMPDIR#$BATS_TEST_TMPDIR#g" | \
  sed "s#\$BATS_RUN_TMPDIR#$BATS_RUN_TMPDIR#g" | \
  (if [[ -n $REMOTE_ADDR ]]; then sed "s#\$REMOTE_ADDR#$REMOTE_ADDR#g"; else cat; fi)
}

get_file_structure() {
  # tree counts differently depending on the version, so we cut off the summary
  (cd "${1:-.}"; tree -n -p --charset=UTF-8 -a -I .git . | head -n-1) 2>&1
}

has_tag() {
  contains_element "$1" "${BATS_TEST_TAGS[@]}"
}

contains_element() {
  local e match="$1"; shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}
