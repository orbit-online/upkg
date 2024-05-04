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
  setup_remote
}

teardown_suite() {
  if [[ -n $REMOTE_PID ]]; then
    kill -INT "$REMOTE_PID" 2>/dev/null
    wait "$REMOTE_PID" || printf "Webserver exited with status code %d\n" "$?" >&2
  fi
}

# Sets up a directory for upkg with only the barest of essentials and creates a upkg wrapper which overwrites PATH with it
setup_upkg_path_wrapper() {
  ${RESTRICT_BIN:-true} || return 0
  if [[ -e /restricted/restricted-bin ]]; then
    export RESTRICTED_BIN=/restricted/restricted-bin
  else
    export RESTRICTED_BIN=$BATS_RUN_TMPDIR/restricted-bin
    PATH=$BATS_RUN_TMPDIR/upkg-wrapper-bin:$PATH
    "$BATS_TEST_DIRNAME/lib/setup-upkg-path-wrapper.sh" "$(realpath "$BATS_TEST_DIRNAME/../bin/upkg")" "$BATS_RUN_TMPDIR"
  fi
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
    printf "The following paths in tests/package-templates have incorrect permissions (fix with \`chmod -R u=rwX,g=rX,o=rX tests/package-templates\`):\n%s" "$wrong_mode_paths" >&2
    return 1
  fi
}

setup_package_fixture_templates() {
  # Global dirs
  export PACKAGE_TEMPLATES PACKAGE_FIXTURES
  PACKAGE_TEMPLATES=$BATS_RUN_TMPDIR/package-templates
  PACKAGE_FIXTURES=$BATS_RUN_TMPDIR/package-fixtures
  mkdir -p "$PACKAGE_FIXTURES"
  cp -r "$BATS_TEST_DIRNAME/package-templates" "$PACKAGE_TEMPLATES"
  local group template
  for group in "$PACKAGE_TEMPLATES"/*; do
    for template in "$group"/*; do
      if [[ -f $template/upkg.json ]]; then
        sed -i "s#\$BATS_RUN_TMPDIR#$BATS_RUN_TMPDIR#g" "$template/upkg.json"
        sed -i "s#\$REMOTE_ADDR#$REMOTE_ADDR#g" "$template/upkg.json"
      fi
    done
  done
}

# Setup webserver to serve package fixtures
setup_package_fixtures_remote() {
  export REMOTE_LOG=$BATS_RUN_TMPDIR/httpd.log
  local python
  python=$(which python 2>/dev/null || which python3 2>/dev/null)
  if [[ -n $python ]]; then
    (cd "$PACKAGE_FIXTURES"; exec $python -u -m http.server -b localhost 0 &>"$REMOTE_LOG") & REMOTE_PID=$!
    local listening_line
    wait_timeout=1000
    until [[ -n $listening_line ]]; do
      sleep .01
      listening_line=$(head -n1 "$REMOTE_LOG")
      if ((wait_timeout-- <= 0)); then
        export SKIP_REMOTE="Timed out waiting for the webserver to become available."
        return 0
      fi
    done
    if [[ $listening_line =~ \((http:\/\/[^\)]+)\/\) ]]; then
      export REMOTE_ADDR=${BASH_REMATCH[1]}
      true >"$REMOTE_LOG" # Clear log before returning
    else
      kill -INT "$REMOTE_PID" 2>/dev/null
      export SKIP_REMOTE="Unable to determine server listening port from first log line: $listening_line"
    fi
  else
    export SKIP_REMOTE='python is not available, unable to mock a webserver'
  fi
}
