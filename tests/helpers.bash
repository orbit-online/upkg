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
  # Output and log after every test returning
  cat "$SERVER_LOG" >&2
  true >"$SERVER_LOG"
}

common_teardown_file() {
  :
}

remove_commands() {
  cp -r "$RESTRICTED_PATH" "$BATS_TEST_TMPDIR/restricted-path"
  local cmd
  for cmd in "$@"; do
    # Don't fail if the command doesn't exist in the first place (e.g. optional dependency)
    rm -f "$BATS_TEST_TMPDIR/restricted-path/$cmd"
  done
  RESTRICTED_PATH="$BATS_TEST_TMPDIR/restricted-path"
}

create_tar_package() {
  local tpl=$PACKAGE_TEMPLATES/$1 dest=$PACKAGE_FIXTURES/$1.tar
  [[ -z $SKIP_TAR ]] || skip "$SKIP_TAR"
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
    printf -- "-- output differs --\n%s" "${out#$'\n'}" | fail
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
      sed "s#$BATS_TEST_TMPDIR#\$BATS_TEST_TMPDIR#g" <<<"$output" | sed "s#$BATS_RUN_TMPDIR#\$BATS_RUN_TMPDIR#g" > "$snapshot_path"
    else
      fail "The snapshot '${snapshot_path%"$SNAPSHOTS"}' does not exist, run with CREATE_SNAPSHOTS=true to create it"
    fi
  elif ${UPDATE_SNAPSHOTS:-false}; then
    # shellcheck disable=SC2001
    sed "s#$BATS_TEST_TMPDIR#\$BATS_TEST_TMPDIR#g" <<<"$output" | sed "s#$BATS_RUN_TMPDIR#\$BATS_RUN_TMPDIR#g" > "$snapshot_path"
  fi
  assert_equals_diff "$(sed "s#\$BATS_TEST_TMPDIR#$BATS_TEST_TMPDIR#g" "$snapshot_path" | sed "s#\$BATS_RUN_TMPDIR#$BATS_RUN_TMPDIR#g")" "$actual"
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

get_file_structure() (
  [[ -z $1 ]] || cd "$1"
  tree -n -p --charset=UTF-8 -a -I .git . 2>&1
)
