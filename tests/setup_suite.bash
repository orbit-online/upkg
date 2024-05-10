#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit nullglob

setup_suite() {
  bats_require_minimum_version 1.5.0
  setup_upkg_path_wrapper
  # Optionally show diff with delta
  export DELTA=cat
  if type delta &>/dev/null; then
    DELTA="delta --hunk-header-style omit"
  fi
  setup_reproducible_vars
  check_commands
  export PACKAGE_FIXTURES
  PACKAGE_FIXTURES=$BATS_RUN_TMPDIR/package-fixtures
  mkdir -p "$PACKAGE_FIXTURES"
  export UPKG_SEQUENTIAL=true
  umask 022 # Make sure permissions of new files match what we expect
  setup_package_fixtures_httpd
  setup_package_fixtures_sshd
  check_package_fixture_template_permissions
  setup_package_fixture_templates
}

teardown_suite() {
  if [[ -n $HTTPD_PKG_FIXTURES_PID ]]; then
    kill -INT "$HTTPD_PKG_FIXTURES_PID" 2>/dev/null
    wait "$HTTPD_PKG_FIXTURES_PID" || printf "HTTP server exited with status code %d\n" "$?" >&2
  fi
  if [[ -n $SSHD_PKG_FIXTURES_PID ]]; then
    kill -INT "$SSHD_PKG_FIXTURES_PID" 2>/dev/null
    wait "$SSHD_PKG_FIXTURES_PID" || printf "HTTP server exited with status code %d\n" "$?" >&2
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

# Check availability of various commands and set $SKIP_* vars whose values are skip messages
check_commands() {
  # Check tar availability and version
  if type tar &>/dev/null; then
    local tar_actual_version tar_expected_version='tar (GNU tar) 1.34'
    tar_actual_version=$(tar --version | head -n1)
    if [[ $tar_actual_version != "$tar_expected_version" ]]; then
      export SKIP_TAR="tar reported version ${tar_actual_version#tar (GNU tar) }. Only ${tar_expected_version#tar (GNU tar) } is supported. Use tests/run.sh to run the tests in a container"
    fi
  else
    export SKIP_TAR='tar is not available. Use tests/run.sh to run the tests in a container.'
  fi
  type git &>/dev/null || export SKIP_GIT='git is not available. Use tests/run.sh to run the tests in a container.'
  type wget &>/dev/null || export SKIP_WGET='wget is not available. Use tests/run.sh to run the tests in a container.'
  type curl &>/dev/null || export SKIP_CURL='curl is not available. Use tests/run.sh to run the tests in a container.'
  type column &>/dev/null || export SKIP_LIST='column is not available. Use tests/run.sh to run the tests in a container.'
  type bzip2 &>/dev/null || export SKIP_BZIP2='bzip2 compression is not available. Use tests/run.sh to run the tests in a container.'
  type xz &>/dev/null || export SKIP_XZ='xz compression is not available. Use tests/run.sh to run the tests in a container.'
  type lzip &>/dev/null || export SKIP_LZIP='lzip compression is not available. Use tests/run.sh to run the tests in a container.'
  type lzma &>/dev/null || export SKIP_LZMA='lzma compression is not available. Use tests/run.sh to run the tests in a container.'
  type lzop &>/dev/null || export SKIP_LZOP='lzop compression is not available. Use tests/run.sh to run the tests in a container.'
  type gzip &>/dev/null || export SKIP_GZIP='gzip compression is not available. Use tests/run.sh to run the tests in a container.'
  type compress &>/dev/null || export SKIP_COMPRESS='z compression is not available. Use tests/run.sh to run the tests in a container.'
  type zstd &>/dev/null || export SKIP_ZSTD='zstd compression is not available. Use tests/run.sh to run the tests in a container.'
}

# Make sure the package-templates have the correct permissions (i.e. git checkout wasn't run with a 002 instead of 022 umask)
check_package_fixture_template_permissions() {
  local wrong_mode_paths
  if wrong_mode_paths=$(find "$BATS_TEST_DIRNAME/package-templates" -not -type l -exec bash -c 'printf "%s %s\n" "$1" "$(stat -c %a "$1")"' -- \{\} \; | grep -v '644$\|755$'); then
    printf "The following paths in tests/package-templates have incorrect permissions (fix with \`chmod -R u=rwX,g=rX,o=rX tests/package-templates\`):\n%s" "$wrong_mode_paths" >&2
    return 1
  fi
}

setup_package_fixture_templates() {
  # Global dirs
  export PACKAGE_TEMPLATES
  PACKAGE_TEMPLATES=$BATS_RUN_TMPDIR/package-templates
  cp -r "$BATS_TEST_DIRNAME/package-templates" "$PACKAGE_TEMPLATES"
  local group template
  for group in "$PACKAGE_TEMPLATES"/*; do
    for template in "$group"/*; do
      if [[ -f $template/upkg.json ]]; then
        sed -i "s#\$BATS_RUN_TMPDIR#$BATS_RUN_TMPDIR#g" "$template/upkg.json"
        sed -i "s#\$PACKAGE_FIXTURES#$PACKAGE_FIXTURES#g" "$template/upkg.json"
        sed -i "s#\$HTTPD_PKG_FIXTURES_ADDR#$HTTPD_PKG_FIXTURES_ADDR#g" "$template/upkg.json"
        sed -i "s#\$SSHD_PKG_FIXTURES_ADDR#$SSHD_PKG_FIXTURES_ADDR#g" "$template/upkg.json"
      fi
    done
  done
}

# Setup HTTP server to serve package fixtures
setup_package_fixtures_httpd() {
  export SKIP_HTTPD_PKG_FIXTURES
  local python
  if ! python=$(which python 2>/dev/null || which python3 2>/dev/null); then
    SKIP_HTTPD_PKG_FIXTURES='python is not available. Use tests/run.sh to run the tests in a container.'
    return 0
  fi
  export HTTPD_PKG_FIXTURES_LOG=$BATS_RUN_TMPDIR/httpd.log
  (cd "$PACKAGE_FIXTURES"; exec "$python" -u -m http.server -b localhost 0 &>"$HTTPD_PKG_FIXTURES_LOG") & HTTPD_PKG_FIXTURES_PID=$!
  local listening_line
  wait_timeout=1000
  until [[ -n $listening_line ]]; do
    sleep .01
    listening_line=$(head -n1 "$HTTPD_PKG_FIXTURES_LOG")
    if ((wait_timeout-- <= 0)); then
      kill -INT "$HTTPD_PKG_FIXTURES_PID" 2>/dev/null
      unset HTTPD_PKG_FIXTURES_PID
      fatal "Timed out waiting for the HTTP server to become available. Use \"--filter-tags '!http'\" to skip HTTP tests."
    fi
  done
  if [[ $listening_line =~ \((http:\/\/[^\)]+)\/\) ]]; then
    export HTTPD_PKG_FIXTURES_ADDR=${BASH_REMATCH[1]}
    true >"$HTTPD_PKG_FIXTURES_LOG" # Clear log before returning
  else
    kill -INT "$HTTPD_PKG_FIXTURES_PID" 2>/dev/null
    unset HTTPD_PKG_FIXTURES_PID
    SKIP_HTTPD_PKG_FIXTURES="Unable to determine server listening port from first log line: $listening_line"
  fi
}

# Setup SSH server to serve git package fixtures
setup_package_fixtures_sshd() {
  export SKIP_SSHD_PKG_FIXTURES
  local python
  if ! python=$(which python 2>/dev/null || which python3 2>/dev/null); then
    SKIP_SSHD_PKG_FIXTURES='python is not available (needed to find a free port for sshd). Use tests/run.sh to run the tests in a container.'
    return 0
  fi
  local sshd
  if ! sshd=$(which sshd 2>/dev/null); then
    SKIP_SSHD_PKG_FIXTURES='sshd is not available. Use tests/run.sh to run the tests in a container.'
    return 0
  fi
  if [[ -z $TMPDIR || $(stat -c %U "$TMPDIR") != "$USER" || ! $(stat -c %a "$TMPDIR") =~ ^7[0-7][0-7]$ ]]; then
    local tmpdir=$BATS_TEST_DIRNAME/bats-tmp
    [[ $BATS_TEST_DIRNAME/bats-tmp != "$PWD"/* ]] || tmpdir=\$PWD/${BATS_TEST_DIRNAME#"$PWD/"}/bats-tmp
    SKIP_SSHD_PKG_FIXTURES="For SSH tests to pass \$TMPDIR must be set to a user owned directory with normal permissions. Set TMPDIR=$tmpdir or use tests/run.sh to run the tests in a container"
    return 0
  fi
  local sshd_root="$BATS_RUN_TMPDIR/ssh/root" sshd_port
  export SSHD_PKG_FIXTURES_LOG=$sshd_root.log SSH_CONFIG=$sshd_root/ssh_config GIT_SSH_COMMAND
  mkdir -p "$sshd_root"
  sshd_port=$("$python" -c 'import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("", 0))
addr = s.getsockname()
print(addr[1])
s.close()')
  SSHD_ROOT=$sshd_root SSHD_PORT=$sshd_port envsubst <"$BATS_TEST_DIRNAME/assets/sshd_config" >"$sshd_root/sshd_config"
  ssh-keygen -q -N '' -t ed25519 -f "$sshd_root/ssh_host_ed25519"
  ssh-keygen -q -N '' -t ed25519 -f "$sshd_root/ssh_client_ed25519"
  (cd "$sshd_root"; exec $sshd -D -E "$SSHD_PKG_FIXTURES_LOG" -f "$sshd_root/sshd_config") & SSHD_PKG_FIXTURES_PID=$!
  local listening_line
  wait_timeout=1000
  until [[ -n $listening_line ]]; do
    sleep .01
    listening_line=$(head -n1 "$SSHD_PKG_FIXTURES_LOG")
    if ((wait_timeout-- <= 0)); then
      kill -INT "$SSHD_PKG_FIXTURES_PID" 2>/dev/null
      unset SSHD_PKG_FIXTURES_PID
      fatal "Timed out waiting for sshd to become available. Use \"--filter-tags '!ssh'\" to skip SSH tests."
    fi
  done
  if [[ $listening_line =~ Server\ listening\ on\ ([^ ]+)\ port\ ([0-9]+)\. ]]; then
    export SSHD_PKG_FIXTURES_HOST=${BASH_REMATCH[1]}
    export SSHD_PKG_FIXTURES_PORT=${BASH_REMATCH[2]}
    true >"$SSHD_PKG_FIXTURES_LOG" # Clear log before returning
  else
    kill -INT "$SSHD_PKG_FIXTURES_PID" 2>/dev/null
    fatal "Unable to determine server listening port from first log line (use \"--filter-tags '!ssh'\" to skip SSH tests): %s." "$listening_line"
  fi
  SSHD_ROOT=$sshd_root envsubst <"$BATS_TEST_DIRNAME/assets/ssh_config" >"$SSH_CONFIG"
  chmod -R go-rwx "$BATS_RUN_TMPDIR/ssh"
  GIT_SSH_COMMAND="ssh -F $(printf "%q" "$SSH_CONFIG")"
}

fatal() {
  local tpl=$1; shift
  # shellcheck disable=SC2059
  printf -- "$tpl\n" "$@" >&2
  return 1
}
