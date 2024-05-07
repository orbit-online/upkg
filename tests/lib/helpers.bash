#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file

common_setup_file() {
  export SNAPSHOTS_ROOT SNAPSHOTS
  SNAPSHOTS_ROOT=$BATS_TEST_DIRNAME/snapshots
  SNAPSHOTS=$SNAPSHOTS_ROOT/$(basename "$BATS_TEST_FILENAME" .bats)
}

common_setup() {
  ! has_tag http || [[ -z $SKIP_HTTPD_PKG_FIXTURES ]] || skip "$SKIP_HTTPD_PKG_FIXTURES"
  ! has_tag ssh || [[ -z $SKIP_SSHD_PKG_FIXTURES ]] || skip "$SKIP_SSHD_PKG_FIXTURES"
  ! has_tag tar || [[ -z $SKIP_TAR ]] || skip "$SKIP_TAR"
  ! has_tag git || [[ -z $SKIP_GIT ]] || skip "$SKIP_GIT"
  ! has_tag wget || [[ -z $SKIP_WGET ]] || skip "$SKIP_WGET"
  ! has_tag curl || [[ -z $SKIP_CURL ]] || skip "$SKIP_CURL"
  ! has_tag list || [[ -z $SKIP_LIST ]] || skip "$SKIP_LIST"
  ! has_tag bzip2 || [[ -z $SKIP_BZIP2 ]] || skip "$BZIP2"
  ! has_tag xz || [[ -z $SKIP_XZ ]] || skip "$XZ"
  ! has_tag lzip || [[ -z $SKIP_LZIP ]] || skip "$LZIP"
  ! has_tag lzma || [[ -z $SKIP_LZMA ]] || skip "$LZMA"
  ! has_tag lzop || [[ -z $SKIP_LZOP ]] || skip "$LZOP"
  ! has_tag gzip || [[ -z $SKIP_GZIP ]] || skip "$GZIP"
  ! has_tag z || [[ -z $SKIP_COMPRESS ]] || skip "$COMPRESS"
  ! has_tag zstd || [[ -z $SKIP_ZSTD ]] || skip "$ZSTD"
  export \
    HOME=$BATS_TEST_TMPDIR/home \
    GLOBAL_INSTALL_PREFIX=$BATS_TEST_TMPDIR/usr \
    PROJECT_ROOT=$BATS_TEST_TMPDIR/project
  export CLEAR_FIXTURES=()
  # EUID cannot be set, so even when running as root make sure to install to $HOME
  export INSTALL_PREFIX=$HOME/.local
  # Don't let upkg run installs in parallel, this results in non-deterministic ouput
  mkdir "$HOME" "$GLOBAL_INSTALL_PREFIX" "$PROJECT_ROOT"
  cd "$PROJECT_ROOT"
}

common_teardown() {
  if [[ -n $(jobs -p) ]]; then
    fail "There were unterminated background jobs after test completion"
  fi
  if [[ -e $HTTPD_PKG_FIXTURES_LOG ]]; then
    if has_tag http; then
      # Output and clear server log after every test
      printf -- "-- httpd logs --\n" >&2
      cat "$HTTPD_PKG_FIXTURES_LOG" >&2
      true >"$HTTPD_PKG_FIXTURES_LOG"
    elif [[ $(stat -c %s "$HTTPD_PKG_FIXTURES_LOG") -gt 0 ]]; then
      true >"$HTTPD_PKG_FIXTURES_LOG"
      fail "HTTP server was accessed but test did not have 'http' tag, you must tag tests that access the HTTP server ('# bats test_tags=http')"
    fi
  fi
  if [[ -e $SSHD_PKG_FIXTURES_LOG ]]; then
    if has_tag ssh; then
      # Output and clear server log after every test
      printf -- "-- sshd logs --\n" >&2
      cat "$SSHD_PKG_FIXTURES_LOG" >&2
      true >"$SSHD_PKG_FIXTURES_LOG"
    elif [[ $(stat -c %s "$SSHD_PKG_FIXTURES_LOG") -gt 0 ]]; then
      true >"$SSHD_PKG_FIXTURES_LOG"
      fail "SSH server was accessed but test did not have 'ssh' tag, you must tag tests that access the SSH server ('# bats test_tags=ssh')"
    fi
  fi
  local fixture
  for fixture in "${CLEAR_FIXTURES[@]}"; do
    rm -rf "$fixture"
  done
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
  local tpl=$PACKAGE_TEMPLATES/$1
  local name_override=$2
  has_tag tar || fail "create_tar_package is used, but the test is not tagged with 'tar'"
  local compression_suffix=$3
  local dest=$PACKAGE_FIXTURES/$1.tar$compression_suffix
  if [[ -n $compression_suffix ]]; then
    has_tag "${compression_suffix#\.}" || \
      fail "create_tar_package is used with ${compression_suffix#\.} compression, but the test is not tagged with '${compression_suffix#\.}'"
  fi
  mkdir -p "$(dirname "$dest")"
  # https://reproducible-builds.org/docs/archives/
  if [[ ! -e "$dest" ]]; then
    tar \
      --sort=name \
      --mtime="@${SOURCE_DATE_EPOCH}" \
      --owner=0 --group=0 --numeric-owner \
      -caf "$dest" -C "$tpl" .
  fi
  if [[ -n $name_override ]]; then
    cp "$dest" "$PACKAGE_FIXTURES/$name_override"
    CLEAR_FIXTURES+=("$PACKAGE_FIXTURES/$name_override")
  fi
  # shellcheck disable=SC2034
  TAR_SHASUM=$(shasum -a 256 "$dest" | cut -d' ' -f1)
}

create_file_package() {
  has_tag file || fail "create_file_package is used, but the test is not tagged with 'file'"
  local tpl=$PACKAGE_TEMPLATES/$1 dest=$PACKAGE_FIXTURES/${2:-$1}
  [[ -z $2 ]] || CLEAR_FIXTURES+=("$dest_name")
  mkdir -p "$(dirname "$dest")"
  [[ -e $dest ]] || cp "$tpl" "$dest"
  # shellcheck disable=SC2034
  FILE_SHASUM=$(shasum -a 256 "$dest" | cut -d' ' -f1)
}

create_git_package() {
  has_tag git || fail "create_git_package is used, but the test is not tagged with 'git'"
  local tpl=$PACKAGE_TEMPLATES/$1 working_copy=$PACKAGE_FIXTURES/$1.git-tmp dest=$PACKAGE_FIXTURES/${2:-$1}.git
  [[ -z $2 ]] || CLEAR_FIXTURES+=("$dest")
  if [[ ! -e $dest ]]; then
    mkdir -p "$(dirname "$dest")"
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
  local actual=${2:-$output} snapshot_path
  if [[ $1 = */* ]]; then
    snapshot_path=$SNAPSHOTS_ROOT/$1.out
  elif [[ -n $1 ]]; then
    snapshot_path=$SNAPSHOTS/$1.out
  else
    snapshot_path=$SNAPSHOTS/${BATS_TEST_DESCRIPTION//'/'/_}.out
  fi
  if [[ ! -e "$snapshot_path" ]]; then
    if ${CREATE_SNAPSHOTS:-false}; then
      mkdir -p "$(dirname "$snapshot_path")"
      # shellcheck disable=SC2001
      replace_values <<<"$actual" > "$snapshot_path"
    else
      fail "The snapshot '${snapshot_path%"$SNAPSHOTS_ROOT"}' does not exist, run with CREATE_SNAPSHOTS=true to create it"
    fi
  elif ${UPDATE_SNAPSHOTS:-false}; then
    # shellcheck disable=SC2001
    replace_values <<<"$actual" > "$snapshot_path"
  fi
  assert_equals_diff "$(replace_vars "$snapshot_path")" "$actual"
}

assert_snapshot_path() {
  local actual_path=${2:-.} snapshot_path
  if [[ $1 = */* ]]; then
    snapshot_path=$SNAPSHOTS_ROOT/$1.files
  elif [[ -n $1 ]]; then
    snapshot_path=$SNAPSHOTS/$1.files
  else
    snapshot_path=$SNAPSHOTS/${BATS_TEST_DESCRIPTION//'/'/_}.files
  fi
  if [[ ! -e "$snapshot_path" ]]; then
    if ${CREATE_SNAPSHOTS:-false}; then
      mkdir -p "$(dirname "$snapshot_path")"
      get_file_structure "$actual_path" > "$snapshot_path"
    else
      fail "The snapshot '${snapshot_path%"$SNAPSHOTS_ROOT"}' does not exist, run with CREATE_SNAPSHOTS=true to create it"
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
  (if [[ -n $HTTPD_PKG_FIXTURES_ADDR ]]; then sed "s#$HTTPD_PKG_FIXTURES_ADDR#\$HTTPD_PKG_FIXTURES_ADDR#g"; else cat; fi)
}

# shellcheck disable=SC2120
replace_vars() {
  (if [[ -n $1 ]]; then cat "$1"; else cat; fi) | \
  sed "s#\$BATS_TEST_TMPDIR#$BATS_TEST_TMPDIR#g" | \
  sed "s#\$BATS_RUN_TMPDIR#$BATS_RUN_TMPDIR#g" | \
  (if [[ -n $HTTPD_PKG_FIXTURES_ADDR ]]; then sed "s#\$HTTPD_PKG_FIXTURES_ADDR#$HTTPD_PKG_FIXTURES_ADDR#g"; else cat; fi)
}

get_file_structure() {
  # tree counts differently depending on the version, so we cut off the summary
  (cd "${1:?}"; tree -n -p --charset=UTF-8 -a -I .git . | head -n-2) 2>&1
}

has_tag() {
  contains_element "$1" "${BATS_TEST_TAGS[@]}"
}

contains_element() {
  local e match="$1"; shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}
