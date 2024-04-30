#!/usr/bin/env bash
set -Eeo pipefail

bats_load_library bats-support
bats_load_library bats-assert

common_setup_file() {
  bats_require_minimum_version 1.5.0
  PATH=$(realpath "$BATS_TEST_DIRNAME/../bin"):$PATH
  local suite_name
  suite_name=$(basename "$BATS_TEST_FILENAME" .bats)
  # Global dirs
  export \
    SNAPSHOTS=$BATS_TEST_DIRNAME/snapshots/$suite_name \
    PACKAGE_TEMPLATES=$BATS_TEST_DIRNAME/package-templates \
    PACKAGE_FIXTURES=$BATS_RUN_TMPDIR/package-fixtures
  mkdir -p "$SNAPSHOTS" "$PACKAGE_FIXTURES"
  # Ensure stable file sorting
  export LC_ALL=
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
  export DELTA=cat
  if type delta &>/dev/null; then
    DELTA="delta --hunk-header-style omit"
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
    wait
  fi
}

common_teardown_file() {
  :
}

create_tar_package() {
  local tpl=$PACKAGE_TEMPLATES/$1 dest=$PACKAGE_FIXTURES/$1.tar
  # https://reproducible-builds.org/docs/archives/
  [[ -e "$dest" ]] || tar \
    --sort=name \
    --mtime="@${SOURCE_DATE_EPOCH}" \
    --owner=0 --group=0 --numeric-owner \
    --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
    -cf "$dest" -C "$tpl" .
  shasum -a 256 "$dest" | cut -d' ' -f1
}

create_git_package() {
  local tpl=$PACKAGE_TEMPLATES/$1 dest=$PACKAGE_FIXTURES/$1.git
  if [[ ! -e $dest ]]; then
    git init -q  "$dest"
    cp -r "$tpl/." "$dest/"
    git -C "$dest" add -A
    git -C "$dest" commit -q --no-gpg-sign -m 'Initial import'
  fi
  git -C "$dest" rev-parse HEAD
}

assert_output_diff() {
  local expected=$1 out
  # Preserving trailing newlines is super cumbersome, let's hope we don't need it
  # shellcheck disable=SC2154
  if ! out=$(diff --color=always --label=expected --label=actual -su <(printf -- "%s\n" "$expected") <(printf -- "%s\n" "$output") | $DELTA); then
    printf -- "-- output differs --\n%s" "$out" | fail
  fi
}

assert_output_file() {
  local output_file=$SNAPSHOTS/${1:-$BATS_TEST_DESCRIPTION}.out
  if ${UPDATE_SNAPSHOTS:-false}; then
    # shellcheck disable=SC2001,SC2154
    sed "s#$BATS_RUN_TMPDIR#\$BATS_RUN_TMPDIR#g" <<<"$output" >"$output_file"
  fi
  assert_output_diff "$(sed "s#\$BATS_RUN_TMPDIR#$BATS_RUN_TMPDIR#g" "$output_file")"
}

assert_file_structure() (
  [[ -z $1 ]] || cd "$1"
  local output_file=$SNAPSHOTS/${2:-$BATS_TEST_DESCRIPTION}.files \
    treecmd="tree -n --charset=UTF-8 -a -I .git ."
  if ${UPDATE_SNAPSHOTS:-false}; then
    # shellcheck disable=SC2001,SC2154
    $treecmd > "$output_file"
  fi
  run $treecmd
  assert_output_diff "$(cat "$output_file")"
)

serve_file() {
  nc -l 8080 < <(
    printf -- 'HTTP/1.1 200 OK\r\nDate: %s\r\nContent-Length: %d\r\n\r\n' \
      "$(date -R)" "$(stat --format='%s' "$1")"
    cat "$1"
  ) &>/dev/null & SERVE_PIDS+=($!)
}
