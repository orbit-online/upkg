#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

bats_load_library bats-support
bats_load_library bats-assert
bats_load_library bats-file
load 'lib/httpd'
load 'lib/sshd'
load 'lib/close-fds'

common_setup_file() {
  export SNAPSHOTS_ROOT SNAPSHOTS
  SNAPSHOTS_ROOT=$BATS_TEST_DIRNAME/snapshots
  SNAPSHOTS=$SNAPSHOTS_ROOT/$(basename "$BATS_TEST_FILENAME" .bats)
}

common_setup() {
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
  if has_tag no-upkg; then
    PATH=$UPKG_ERROR_PATH
  else
    PATH=$UPKG_WRAPPER_PATH
    [[ -z $SKIP_UPKG ]] || skip "$SKIP_UPKG"
  fi
  if has_tag http; then
    [[ -z $SKIP_HTTPD ]] || skip "$SKIP_HTTPD"
    setup_package_fixtures_httpd
  fi
  if has_tag ssh; then
    [[ -z $SKIP_SSHD ]] || skip "$SKIP_SSHD"
    setup_package_fixtures_sshd
  fi
  export \
    HOME=$BATS_TEST_TMPDIR/home \
    GLOBAL_INSTALL_PREFIX=$BATS_TEST_TMPDIR/usr \
    PROJECT_ROOT=$BATS_TEST_TMPDIR/project \
    TEST_PACKAGE_FIXTURES=$BATS_TEST_TMPDIR/package-fixtures
  export SNAPSHOT_CREATED=false SNAPSHOT_UPDATED=false
  # EUID cannot be set, so even when running as root make sure to install to $HOME
  export INSTALL_PREFIX=$HOME/.local
  # Don't let upkg run installs in parallel, this results in non-deterministic ouput
  mkdir "$HOME" "$GLOBAL_INSTALL_PREFIX" "$PROJECT_ROOT"
  cd "$PROJECT_ROOT"
}

common_teardown() {
  local ret=0
  ! has_tag http || teardown_package_fixtures_httpd
  ! has_tag ssh || teardown_package_fixtures_sshd
  if [[ -n $(jobs -p) ]]; then
    fail "There were unterminated background jobs after test completion"
    ret=1
  fi
  if [[ -e $BATS_TEST_TMPDIR/snapshot-created ]]; then
    fail "Snapshots were created during this run. Inspect and validate them, then run the tests again to ensure that they are stable"
    ret=1
  fi
  if [[ -e $BATS_TEST_TMPDIR/snapshot-updated ]]; then
    fail "Snapshots were updated during this run. Inspect and validate them, then run the tests again to ensure that they are stable"
    ret=1
  fi
  [[ $ret = 0 ]] || exit $ret
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
  has_tag tar || fail "create_tar_package is used, but the test is not tagged with 'tar'"
  local compression_suffix=$3
  local dest=$PACKAGE_FIXTURES/$1.tar$compression_suffix
  if [[ -n $compression_suffix ]]; then
    has_tag "${compression_suffix#\.}" || \
      fail "create_tar_package is used with ${compression_suffix#\.} compression, but the test is not tagged with '${compression_suffix#\.}'"
  fi
  [[ -z $2 ]] || dest=$TEST_PACKAGE_FIXTURES/$2
  mkdir -p "$(dirname "$dest")"
  (
    close_non_std_fds
    exec 9<>"$dest.lock"
    trap "exec 9>&-" EXIT # Release as soon as are done
    if ! flock -nx 9; then
      flock -s 9 # Wait for exclusive lock to be release (and tar to be finished)
    else
      # https://reproducible-builds.org/docs/archives/
      [[ -e "$dest" ]] || tar \
        --sort=name \
        --mode='u+rwX,g-w,o-w' \
        --mtime="@${SOURCE_DATE_EPOCH}" \
        --owner=0 --group=0 --numeric-owner \
        -caf "$dest" -C "$tpl" .
    fi
  )
  # shellcheck disable=SC2034
  TAR_SHASUM=$(shasum -a 256 "$dest" | cut -d' ' -f1)
}

create_file_package() {
  has_tag file || fail "create_file_package is used, but the test is not tagged with 'file'"
  local tpl=$PACKAGE_TEMPLATES/$1 dest=$PACKAGE_FIXTURES/$1
  [[ -z $2 ]] || dest=$TEST_PACKAGE_FIXTURES/$2
  mkdir -p "$(dirname "$dest")"
  cp -n "$tpl" "$dest"
  # shellcheck disable=SC2034
  FILE_SHASUM=$(shasum -a 256 "$dest" | cut -d' ' -f1)
}

create_git_package() {
  has_tag git || fail "create_git_package is used, but the test is not tagged with 'git'"
  local tpl=$PACKAGE_TEMPLATES/$1 working_copy=$PACKAGE_FIXTURES/$1.git-tmp dest=$PACKAGE_FIXTURES/$1.git
  [[ -z $2 ]] || dest=$TEST_PACKAGE_FIXTURES/$2.git
  mkdir -p "$(dirname "$dest")"
  (
    close_non_std_fds
    exec 9<>"$dest.lock"
    trap "exec 9>&-" EXIT # Release as soon as we are done
    if ! flock -nx 9; then
      flock -s 9 # Wait for exclusive lock to be released (and git to be finished)
    else
      if [[ ! -e $dest ]]; then
        mkdir "$working_copy"
        git init -q  "$working_copy"
        cp -r "$tpl/." "$working_copy/"
        git -C "$working_copy" add -A
        git -C "$working_copy" commit -q --no-gpg-sign -m 'Initial import'
        git clone -q --bare "$working_copy" "$dest"
        git -C "$dest" --bare update-server-info
      fi
    fi
  )
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
    mkdir -p "$(dirname "$snapshot_path")"
    # shellcheck disable=SC2001
    replace_values <<<"$actual" > "$snapshot_path"
    touch "$BATS_TEST_TMPDIR/snapshot-created"
  elif ${UPDATE_SNAPSHOTS:-false}; then
    # shellcheck disable=SC2001
    replace_values <<<"$actual" > "$snapshot_path.new"
    if ! diff -q "$snapshot_path" "$snapshot_path.new" &>/dev/null; then
      mv "$snapshot_path.new" "$snapshot_path"
      touch "$BATS_TEST_TMPDIR/snapshot-updated"
    else
      rm "$snapshot_path.new"
    fi
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
    mkdir -p "$(dirname "$snapshot_path")"
    get_file_structure "$actual_path" > "$snapshot_path"
    touch "$BATS_TEST_TMPDIR/snapshot-created"
  elif ${UPDATE_SNAPSHOTS:-false}; then
    get_file_structure "$actual_path" > "$snapshot_path.new"
    if ! diff -q "$snapshot_path" "$snapshot_path.new" &>/dev/null; then
      mv "$snapshot_path.new" "$snapshot_path"
      touch "$BATS_TEST_TMPDIR/snapshot-updated"
    else
      rm "$snapshot_path.new"
    fi
  fi
  assert_equals_diff "$(cat "$snapshot_path")" "$(get_file_structure "$actual_path")"
}

assert_all_links_valid() {
  shopt -s dotglob
  local path=${1:-.} link_path
  for link_path in "$path"/*; do
    [[ -e $link_path ]] || fail "The symlink at '$link_path' points to a non-existent path: '$(readlink "$link_path")'"
    [[ ! -d $link_path ]] || assert_all_links_valid "$link_path"
  done
  shopt -u dotglob
}

# shellcheck disable=SC2120
replace_values() {
  local data
  if [[ -n $1 ]]; then data=$(cat "$1")
  else data=$(cat); fi
  data=${data//"$BATS_TEST_TMPDIR"/\$BATS_TEST_TMPDIR}
  data=${data//"$BATS_RUN_TMPDIR"/\$BATS_RUN_TMPDIR}
  [[ -z $HTTPD_PKG_FIXTURES_ADDR ]] || data=${data//"$HTTPD_PKG_FIXTURES_ADDR"/\$HTTPD_PKG_FIXTURES_ADDR}
  printf "%s\n" "$data"
}

# shellcheck disable=SC2120
replace_vars() {
  local data
  if [[ -n $1 ]]; then data=$(cat "$1")
  else data=$(cat); fi
  data=${data//\$BATS_TEST_TMPDIR/"$BATS_TEST_TMPDIR"}
  data=${data//\$BATS_RUN_TMPDIR/"$BATS_RUN_TMPDIR"}
  [[ -z $HTTPD_PKG_FIXTURES_ADDR ]] || data=${data//\$HTTPD_PKG_FIXTURES_ADDR/"$HTTPD_PKG_FIXTURES_ADDR"}
  printf "%s\n" "$data"
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
