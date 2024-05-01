#!/usr/bin/env bash
set -Eeo pipefail

bats_load_library bats-support
bats_load_library bats-assert

common_setup_file() {
  bats_require_minimum_version 1.5.0
  # Setup path to upkg
  PATH=$(realpath "$BATS_TEST_DIRNAME/../bin"):$PATH
  # Global dirs
  export SNAPSHOTS PACKAGE_TEMPLATES PACKAGE_FIXTURES
  SNAPSHOTS=$BATS_TEST_DIRNAME/snapshots/$(basename "$BATS_TEST_FILENAME" .bats)
  PACKAGE_TEMPLATES=$BATS_TEST_DIRNAME/package-templates
  PACKAGE_FIXTURES=$BATS_RUN_TMPDIR/package-fixtures
  mkdir -p "$SNAPSHOTS" "$PACKAGE_FIXTURES"
  # Optionally show diff with delta
  export DELTA=cat
  if type delta &>/dev/null; then
    DELTA="delta --hunk-header-style omit"
  fi
  # Ensure stable file sorting
  export LC_ALL=C
  # Don't include atime & ctime in tar archives (https://reproducible-builds.org/docs/archives/)
  unset POSIXLY_CORRECT
  # Fixed timestamp for reproducible builds. 2024-01-01T00:00:00Z
  export SOURCE_DATE_EPOCH=1704067200
  # Reproducible git repos
  export \
    GIT_AUTHOR_NAME=Anonymous \
    GIT_AUTHOR_EMAIL=anonymous@example.org \
    GIT_AUTHOR_DATE="$SOURCE_DATE_EPOCH+0000" \
    GIT_COMMITTER_NAME=Anonymous \
    GIT_COMMITTER_EMAIL=anonymous@example.org \
    GIT_COMMITTER_DATE="$SOURCE_DATE_EPOCH+0000"
  # Setup TAR to allow skipping tests with a message
  export SKIP_TAR='tar is not available, use tests/run.sh to run this test in a container'
  if type tar &>/dev/null; then
    local tar_actual_version tar_expected_version='tar (GNU tar) 1.34'
    tar_actual_version=$(tar --version | head -n1)
    SKIP_TAR=
    if [[ $tar_actual_version != "$tar_expected_version" ]]; then
      SKIP_TAR="tar reported version ${tar_actual_version#tar (GNU tar) }. Only ${tar_expected_version#tar (GNU tar) } is supported, use tests/run.sh to run this test in a container"
    fi
  fi
  # Make sure the package-templates have the correct permissions (i.e. git checkout wasn't run with a 002 instead of 022 umask)
  export SKIP_PACKAGE_TEMPLATES=
  if ! (SNAPSHOTS=$BATS_TEST_DIRNAME/snapshots assert_snapshot_files "package-templates" "$BATS_TEST_DIRNAME/package-templates"); then
    SKIP_PACKAGE_TEMPLATES="The package templates do not match the stored snapshot, run the the README to determine how to fix the issue"
  fi
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
  SERVE_PIDS=()
  cd "$PROJECT_ROOT"
}

common_teardown() {
  if (( ${#SERVE_PIDS} != 0 )); then
    kill "${SERVE_PIDS[@]}" 2>/dev/null
    local pid
    for pid in "${SERVE_PIDS[@]}"; do
      wait "$pid"
    done
  fi
  if [[ -n $(jobs -p) ]]; then
    fail "There were unterminated background jobs after test completion"
  fi
}

common_teardown_file() {
  :
}

create_tar_package() {
  local tpl=$PACKAGE_TEMPLATES/$1 dest=$PACKAGE_FIXTURES/$1.tar
  [[ -z $SKIP_PACKAGE_TEMPLATES ]] || skip "$SKIP_PACKAGE_TEMPLATES"
  [[ -z $SKIP_TAR ]] || skip "$SKIP_TAR"
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
  local tpl=$PACKAGE_TEMPLATES/$1 dest=$PACKAGE_FIXTURES/$1.git
  [[ -z $SKIP_PACKAGE_TEMPLATES ]] || skip "$SKIP_PACKAGE_TEMPLATES"
  if [[ ! -e $dest ]]; then
    git init -q  "$dest"
    cp -r "$tpl/." "$dest/"
    git -C "$dest" add -A
    git -C "$dest" commit -q --no-gpg-sign -m 'Initial import'
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

assert_snapshot() {
  local snapshot_name=${1:-$BATS_TEST_DESCRIPTION} actual=${2:-$output}
  snapshot_name=${snapshot_name//'/'/_}
  local snapshot_path=$SNAPSHOTS/$snapshot_name.out
  if [[ ! -e "$snapshot_path" ]]; then
    if ${CREATE_SNAPSHOTS:-false}; then
      # shellcheck disable=SC2001
      sed "s#$BATS_RUN_TMPDIR#\$BATS_RUN_TMPDIR#g" <<<"$output" > "$snapshot_path"
    else
      fail "The snapshot ${snapshot_path%"$SNAPSHOTS"} does not exist, run with CREATE_SNAPSHOTS=true to create it"
    fi
  elif ${UPDATE_SNAPSHOTS:-false}; then
    # shellcheck disable=SC2001
    sed "s#$BATS_RUN_TMPDIR#\$BATS_RUN_TMPDIR#g" <<<"$output" >"$snapshot_path"
  fi
  assert_equals_diff "$(sed "s#\$BATS_RUN_TMPDIR#$BATS_RUN_TMPDIR#g" "$snapshot_path")" "$actual"
}

assert_snapshot_files() {
  local snapshot_name=${1:-$BATS_TEST_DESCRIPTION} actual_path=$2
  snapshot_name=${snapshot_name//'/'/_}
  local snapshot_path=$SNAPSHOTS/$snapshot_name.files
  if [[ ! -e "$snapshot_path" ]]; then
    if ${CREATE_SNAPSHOTS:-false}; then
      get_file_structure "$actual_path" > "$snapshot_path"
    else
      fail "The snapshot ${snapshot_path%"$SNAPSHOTS"} does not exist, run with CREATE_SNAPSHOTS=true to create it"
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

serve_file() {
  nc -l 8080 < <(
    printf -- 'HTTP/1.1 200 OK\r\nDate: %s\r\nContent-Length: %d\r\n\r\n' \
      "$(date -R)" "$(stat --format='%s' "$1")"
    cat "$1"
  ) &>/dev/null & SERVE_PIDS+=($!)
}
