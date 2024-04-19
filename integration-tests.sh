#!/usr/bin/env bash

set -o pipefail

: "${UPKG_PATH?"Must specificy path to upkg binary."}"

for dep in diff tree; do
  type "$dep" &>/dev/null || fatal 'Missing dependency %s' "$dep" || exit 1
done

ERRORED=false
DIR="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
OLDHOME=$HOME
UPDATE_SNAPSHOTS=false

run() {
  local args ctx upkg \
        expected_exitcode expected_stderr expected_stdout \
        actual_exitcode actual_stderr actual_stdout
  upkg="$UPKG_PATH"
  printf -- 'Running tests...\n\n'

  if [[ "$*" =~ -u ]]; then
    UPDATE_SNAPSHOTS=true
  fi
  if [[ $1 == -u ]]; then
    shift
  fi

  for t in "$DIR/tests/"*; do
    [[ -z "$1" || $(basename "$t") == $1* ]] || continue
    export HOME=$OLDHOME
    printf -- '%s\n\n' "$(basename "$t")"
    args=$(cat "$t/args")
    expected_exitcode=$(cat "$t/exitcode" 2>/dev/null || printf -- '-1')
    expected_stdout=$(cat "$t/stdout" 2>/dev/null || printf -- '')
    expected_stderr=$(cat "$t/stderr" 2>/dev/null || printf -- '')

    [[ -n "$ctx" ]] && rm -Rf "$ctx"
    ctx=$(mktemp --tmpdir="${TMPDIR:-/tmp}" -d upkg-test.XXXXXXXXXX)
    # shellcheck disable=SC2064
    trap "rm -Rf '$ctx'" EXIT
    mkdir -p "$ctx/home/" "$ctx/workdir/"
    cd "$ctx/workdir/" || fail 'PANIC! Could not change directory to test context directory' || exit 1
    export HOME="$ctx/home" # manipulate where "global" points to. $HOME/.local

    [[ -d "$t/fixtures-local" ]] && cp -ax "$t/fixtures-local/." "$ctx/workdir/"
    [[ -d "$t/fixtures-global" ]] && cp -ax "$t/fixtures-global/." "$ctx/home/.local/"

    # shellcheck disable=SC2048,SC2086
    {
      # shellcheck disable=SC2059
      printf -- '    $ ./upkg.sh '
      [[ -n ${args[*]} ]] && printf -- '%q ' ${args[*]}
      printf -- '\n'

      IFS=$'\n' read -r -d '' actual_stderr;
      IFS=$'\n' read -r -d '' actual_stdout;
      (IFS=$'\n' read -r -d '' actual_exitcode; exit "${actual_exitcode}");
      actual_exitcode=$?
      printf -- '    exit: %d\n' "$actual_exitcode"
      [[ $actual_exitcode == "$expected_exitcode" || $expected_exitcode == '*' ]] || fail 'status:\n%s\n' "$(diff --color=always --label=actual --label=expected -su <(echo "exit: $actual_exitcode") <(echo "exit: $expected_exitcode"))" || update_snapshot "$t/exitcode" "$actual_exitcode" || continue
      [[ $actual_stdout == "$expected_stdout" || $expected_stdout == '*' ]] || fail 'stdout:\n%s\n' "$(diff --color=always --label=actual --label=expected -su <(echo "$actual_stdout") <(echo "$expected_stdout"))" || update_snapshot "$t/stdout" "$actual_stdout" || continue
      [[ $actual_stderr == "$expected_stderr" || $expected_stderr == '*' ]] || fail 'stderr:\n%s\n' "$(diff --color=always --label=actual --label=expected -su <(echo "$actual_stderr") <(echo "$expected_stderr"))" || update_snapshot "$t/stderr" "$actual_stderr" || continue

      if [[ -d "$t/result-local" ]]; then
        actual_result=$(tree -a "." -I '.gitignore')
        expected_result=$(cd "$t/result-local" && tree -a -I '.gitignore')
        [[ $actual_result == "$expected_result" ]] || fail 'tree local:\n%s\n' "$(diff --color=always --label=actual --label=expected -su <(echo "$actual_result") <(echo "$expected_result"))" || continue
      fi

      if [[ -d "$t/result-global" ]]; then
        actual_result=$(cd $HOME/.local && tree -a "." -I '.gitignore')
        expected_result=$(cd "$t/result-global" && tree -a -I '.gitignore')
        [[ $actual_result == "$expected_result" ]] || fail 'tree global:\n%s\n' "$(diff --color=always --label=actual --label=expected -su <(echo "$actual_result") <(echo "$expected_result"))" || continue
      fi

      printf -- '\n'
    } < <((printf '\0%s\0%d\0' "$("$upkg" ${args[*]})" "${?}" 1>&2) 2>&1)
  done

  [[ -n "$ctx" ]] && rm -Rf "$ctx"
  $UPDATE_SNAPSHOTS && ! $ERRORED && printf -- 'No snapshots were updated\n'
  $ERRORED && printf -- 'Tests finished with error(s)\n' && return 1

  printf -- 'Tests finished succesfully\n'
  return 0
}

fail() {
  ERRORED=true
  $UPDATE_SNAPSHOTS && return 1

  local tpl=$1; shift
  # shellcheck disable=SC2059
  printf -- "fail $tpl\n" "$@" >&2
  return 1
}

update_snapshot() {
  $UPDATE_SNAPSHOTS || return 1

  printf -- '\nUpdating snashot %s with following content:\n%s\n' "$(basename "$(dirname "$1")")/$(basename "$1")" "$2"
  echo "$2" > "$1"
  return 0
}

run "$@"
