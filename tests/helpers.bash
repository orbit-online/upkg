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
  # Reproducible git repos
  export \
    GIT_AUTHOR_NAME=Anonymous \
    GIT_AUTHOR_EMAIL=anonymous@example.org \
    GIT_AUTHOR_DATE='2024-04-29 10:00:00' \
    GIT_COMMITTER_NAME=Anonymous \
    GIT_COMMITTER_EMAIL=anonymous@example.org \
    GIT_COMMITTER_DATE='2024-04-29 10:00:00'
}

common_setup() {
  export \
    HOME=$BATS_TEST_TMPDIR/home \
    GLOBAL_INSTALL_PREFIX=$BATS_TEST_TMPDIR/usr \
    PROJECT_ROOT=$BATS_TEST_TMPDIR/project
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
  [[ -e "$dest" ]] || tar -cf "$dest" -C "$tpl" .
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

assert_output_file() {
  local output_file=$SNAPSHOTS/${1:-$BATS_TEST_DESCRIPTION}.out
  if ${UPDATE_SNAPSHOTS:-false}; then
    # shellcheck disable=SC2001,SC2154
    sed "s#$BATS_RUN_TMPDIR#\$BATS_RUN_TMPDIR#g" <<<"$output" >"$output_file"
  fi
  assert_output "$(sed "s#\$BATS_RUN_TMPDIR#$BATS_RUN_TMPDIR#g" "$output_file")"
}

assert_file_structure() (
  [[ -z $1 ]] || cd "$1"
  local output_file=$SNAPSHOTS/${2:-$BATS_TEST_DESCRIPTION}.files
  if ${UPDATE_SNAPSHOTS:-false}; then
    # shellcheck disable=SC2001,SC2154
    tree -a -I .git . >"$output_file"
  fi
  run tree -a -I .git .
  assert_output "$(cat "$output_file")"
)

serve_file() {
  nc -l 8080 < <(
    printf -- 'HTTP/1.1 200 OK\r\nDate: %s\r\nContent-Length: %d\r\n\r\n' \
      "$(date -R)" "$(stat --format='%s' "$1")"
    cat "$1"
  ) &>/dev/null & SERVE_PIDS+=($!)
}
