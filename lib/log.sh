#!/usr/bin/env bash
# shellcheck disable=SC2059

verbose() {
  $VERBOSE || return 0
  local tpl=$1; shift
  printf -- "upkg: $tpl\n" "$@" >&2
}

processing() {
  ! ${QUIET:-false} || return 0
  local tpl=$1; shift
  if ! $VERBOSE && [[ -t 2 ]]; then
    printf -- "\e[2Kupkg: $tpl\r" "$@" >&2
  else
    printf -- "upkg: $tpl\n" "$@" >&2
  fi
}

completed() {
  processing "$@"
  trailing_newline
}

warning() {
  ! ${QUIET:-false} || return 0
  local tpl=$1; shift
  if ! $VERBOSE && [[ -t 2 ]]; then
    printf -- "\e[2Kupkg: $tpl\n" "$@" >&2
  else
    printf -- "upkg: $tpl\n" "$@" >&2
  fi
}

# Special functions for dry-run.
dry_run_error() {
  # shellcheck disable=SC2034
  DRY_RUN_EXIT=1
  if ! ${QUIET:-false}; then
    local tpl=$1; shift
    if ! $VERBOSE && [[ -t 2 ]]; then
      printf -- "\e[2Kupkg: $tpl\n" "$@" >&2
    else
      printf -- "upkg: $tpl\n" "$@" >&2
    fi
  fi
}

dry_run_fail() {
  dry_run_error "$@"
  return 1
}

fatal() {
  local tpl=$1; shift
  if ! $VERBOSE && [[ -t 2 ]]; then
    printf -- "\e[2Kupkg: $tpl\n" "$@" >&2
  else
    printf -- "upkg: $tpl\n" "$@" >&2
  fi
  return 1
}

# Used for adding a newline at the end of execution
trailing_newline() {
  ! ${QUIET:-false} || return 0
  if ! $VERBOSE && [[ -t 2 ]]; then
    printf "\n"
  fi
}
