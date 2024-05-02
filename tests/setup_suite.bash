#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit

setup_suite() {
  bats_require_minimum_version 1.5.0
  # Global dirs
  export PACKAGE_TEMPLATES PACKAGE_FIXTURES
  PACKAGE_TEMPLATES=$BATS_TEST_DIRNAME/package-templates
  PACKAGE_FIXTURES=$BATS_RUN_TMPDIR/package-fixtures
  mkdir -p "$PACKAGE_FIXTURES"
  setup_upkg_path_wrapper
  # Optionally show diff with delta
  export DELTA=cat
  if type delta &>/dev/null; then
    DELTA="delta --hunk-header-style omit"
  fi
  setup_reproducible_vars
  check_tar
  check_fixture_permissions

  export SERVER_LOG=$BATS_RUN_TMPDIR/httpd.log
  (cd "${1:-$PACKAGE_FIXTURES}"; exec python3 -m http.server 8080 &>"$SERVER_LOG") & SERVE_PID=$!
  wait_timeout=1000
  until wget -qO/dev/null localhost:8080; do
    sleep .01
    if ((wait_timeout-- <= 0)); then
      printf "Timed out waiting for the webserver to become available. Logs:\n%s" "$(cat "$SERVER_LOG")"
      exit 1
    fi
  done
  true >"$SERVER_LOG" # Clear log before returning
}

teardown_suite() {
  kill -INT "$SERVE_PID" 2>/dev/null
  wait "$SERVE_PID" || printf "Webserver exited with status code %d\n" "$?" >&2
}

# Sets up a directory for upkg with only the barest of essentials and creates a upkg wrapper which overwrites PATH with it
setup_upkg_path_wrapper() {
  ${RESTRICT_BIN:-true} || return 0
  export RESTRICTED_PATH=$BATS_RUN_TMPDIR/restricted-path
  local upkg_wrapper_bin
  upkg_wrapper_bin=$BATS_RUN_TMPDIR/upkg-wrapper-bin
  PATH=$upkg_wrapper_bin:$PATH
  [[ ! -e "$BATS_RUN_TMPDIR/restricted-path" ]] || return 0
  local real_upkg_path
  real_upkg_path=$(realpath "$BATS_TEST_DIRNAME/../bin/upkg")
  mkdir -p "$RESTRICTED_PATH" "$upkg_wrapper_bin"
  # shellcheck disable=SC2016
  printf '#/usr/bin/env bash
PATH="$RESTRICTED_PATH" "%s" "$@"
' "$real_upkg_path" >"$upkg_wrapper_bin/upkg"
  chmod +x "$upkg_wrapper_bin/upkg"
  # Make sure the wrapper is invoked when calling upkg

  local cmd target required_commands=(
    bash jq
    basename dirname sort comm cut column # string commands
    mv cp mkdir touch rm find ln chmod cat readlink # fs commands
    sleep flock # concurrency commands
    shasum git tar gzip xz bzip2 # archive commands
  )
  for cmd in "${required_commands[@]}"; do
    target=$(which "$cmd") || fail "Unable to find required command '$cmd'"
    ln -sT "$target" "$RESTRICTED_PATH/$cmd"
  done
  if target=$(which wget 2>/dev/null); then
    ln -sT "$target" "$RESTRICTED_PATH/wget"
  elif target=$(which curl 2>/dev/null); then
    ln -sT "$target" "$RESTRICTED_PATH/curl"
  else
    fatal "Unable to find wget or curl"
  fi
  ln -sT "$real_upkg_path" "$RESTRICTED_PATH/upkg"
}

setup_reproducible_vars() {
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
}

# Setup TAR to allow skipping tests with a message
check_tar() {
  export SKIP_TAR='tar is not available, use tests/run.sh to run this test in a container'
  if type tar &>/dev/null; then
    local tar_actual_version tar_expected_version='tar (GNU tar) 1.34'
    tar_actual_version=$(tar --version | head -n1)
    SKIP_TAR=
    if [[ $tar_actual_version != "$tar_expected_version" ]]; then
      SKIP_TAR="tar reported version ${tar_actual_version#tar (GNU tar) }. Only ${tar_expected_version#tar (GNU tar) } is supported, use tests/run.sh to run this test in a container"
    fi
  fi
}

# Make sure the package-templates have the correct permissions (i.e. git checkout wasn't run with a 002 instead of 022 umask)
check_fixture_permissions() {
  local wrong_mode_paths
  if wrong_mode_paths=$(find "$BATS_TEST_DIRNAME/package-templates" -exec bash -c 'printf "%s %s\n" "$1" "$(stat -c %a "$1")"' -- \{\} \; | grep -v '644$\|755$'); then
    fail "The following paths in tests/package-templates have incorrect permissions (fix with \`chmod -R u=rwX,g=rX,o=rX tests/package-templates\`):
$wrong_mode_paths"
  fi
}
