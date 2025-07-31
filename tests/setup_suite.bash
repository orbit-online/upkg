#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit nullglob

setup_suite() {
  bats_require_minimum_version 1.5.0
  source_distribution_adjustments
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
  setup_package_fixture_templates
}

teardown_suite() {
  :
}

source_distribution_adjustments() {
  # shellcheck disable=SC1090
  if [[ -n $BASEIMG ]]; then
    # shellcheck disable=SC1091
    source "/upkg/tests/assets/dist-adjustments/default.sh"
    [[ ! -e /upkg/tests/assets/dist-adjustments/${BASEIMG%:*}.sh ]] || \
      source "/upkg/tests/assets/dist-adjustments/${BASEIMG%:*}.sh"
    [[ ! -e /upkg/tests/assets/dist-adjustments/$BASEIMG.sh ]] || \
      source "/upkg/tests/assets/dist-adjustments/$BASEIMG.sh"
  fi
}

# Sets up a directory for upkg with only the barest of essentials and creates a upkg wrapper which overwrites PATH with it
setup_upkg_path_wrapper() {
  ${RESTRICT_BIN:-true} || return 0
  mkdir "$BATS_RUN_TMPDIR/upkg-error-bin"
  cp "$BATS_TEST_DIRNAME/assets/upkg-error.sh" "$BATS_RUN_TMPDIR/upkg-error-bin/upkg"
  export UPKG_ERROR_PATH=$BATS_RUN_TMPDIR/upkg-error-bin:$PATH
  if [[ -e /restricted/restricted-bin ]]; then
    export RESTRICTED_BIN=/restricted/restricted-bin
    export UPKG_WRAPPER_PATH=$PATH
  else
    local bash_path
    export RESTRICTED_BIN=$BATS_RUN_TMPDIR/restricted-bin
    export UPKG_WRAPPER_PATH=$BATS_RUN_TMPDIR/upkg-wrapper-bin:$PATH
    [[ -z $TEST_BASH_VERSION ]] || bash_path=$("$BATS_TEST_DIRNAME/lib/get-bash.sh" "$TEST_BASH_VERSION")
    "$BATS_TEST_DIRNAME/lib/setup-upkg-path-wrapper.sh" "$(realpath "$BATS_TEST_DIRNAME/../bin/upkg")" "$BATS_RUN_TMPDIR" "$bash_path"
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
  export TAR_DOCKER=false
  # Check tar availability and version
  if type tar &>/dev/null; then
    local tar_actual_version tar_allowed_versions=('1.34' '1.35') tar_allowed_version
    tar_actual_version=$(tar --version | head -n1)
    export SKIP_TAR="tar reported version ${tar_actual_version#tar (GNU tar) }. Only versions ${tar_allowed_versions[*]} are supported and docker is not available to containerize this operation."
    for tar_allowed_version in "${tar_allowed_versions[@]}"; do
      if [[ $tar_actual_version = *"$tar_allowed_version" ]]; then
        unset SKIP_TAR
        break
      fi
    done
  else
    export SKIP_TAR='tar is not available and neither is docker to containerize this operation.'
  fi
  if [[ -n $SKIP_TAR ]]; then
    if type docker &>/dev/null; then
      unset SKIP_TAR
      TAR_DOCKER=true
    fi
  fi
  local upkg_help
  upkg_help=$("$BATS_TEST_DIRNAME/../bin/upkg" --help 2>&1) || export SKIP_UPKG="Unable to invoke \`upkg --help\`. Make sure to run tools/install-deps.sh first. Output was:\n$upkg_help\n"
  export PYTHON
  if ! PYTHON=$(which python 2>/dev/null || which python3 2>/dev/null); then
    export SKIP_HTTPD='python is not available. Use tests/run.sh to run the tests in a container.'
    export SKIP_SSHD=$SKIP_HTTPD
  fi
  export SSHD
  if SSHD=$(which sshd 2>/dev/null); then
    if [[ -z $TMPDIR || $(stat -c %U "$TMPDIR") != "$USER" || ! $(stat -c %a "$TMPDIR") =~ ^7[0-7][0-7]$ ]]; then
      local tmpdir=$BATS_TEST_DIRNAME/bats-tmp
      [[ $BATS_TEST_DIRNAME/bats-tmp != "$PWD"/* ]] || tmpdir=\$PWD/${BATS_TEST_DIRNAME#"$PWD/"}/bats-tmp
      export SKIP_SSHD="For SSH tests to pass \$TMPDIR must be set to a user owned directory with normal permissions. Set TMPDIR=$tmpdir or use tests/run.sh to run the tests in a container"
    fi
  else
    export SKIP_SSHD='sshd is not available. Use tests/run.sh to run the tests in a container.'
  fi
  { type zip &>/dev/null && type unzip &>/dev/null; } || export SKIP_ZIP='zip/unzip is not available. Use tests/run.sh to run the tests in a container.'
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
  type shellcheck &>/dev/null || export SKIP_SHELLCHECK='shellcheck is not available. Use tests/run.sh to run the tests in a container.'
}

setup_package_fixture_templates() {
  # Global dirs
  export PACKAGE_TEMPLATES
  PACKAGE_TEMPLATES=$BATS_RUN_TMPDIR/package-templates
  cp -R "$BATS_TEST_DIRNAME/package-templates" "$PACKAGE_TEMPLATES"
  local group template upkgjson_path upkgjson
  for group in "$PACKAGE_TEMPLATES"/*; do
    for template in "$group"/*; do
      upkgjson_path=
      [[ $template != *upkg.json ]] || upkgjson_path=$template
      [[ ! -f $template/upkg.json ]] || upkgjson_path=$template/upkg.json
      if [[ -n $upkgjson_path ]]; then
        upkgjson=$(cat "$upkgjson_path")
        upkgjson=${upkgjson//\$BATS_RUN_TMPDIR/"$BATS_RUN_TMPDIR"}
        upkgjson=${upkgjson//\$PACKAGE_FIXTURES/"$PACKAGE_FIXTURES"}
        printf "%s\n" "$upkgjson" >"$upkgjson_path"
      fi
    done
  done
}

fatal() {
  local tpl=$1; shift
  # shellcheck disable=SC2059
  printf -- "$tpl\n" "$@" >&2
  return 1
}
