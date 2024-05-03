#!/usr/bin/env bash

processing() {
  ! ${UPKG_SILENT:-false} || return 0
  local tpl=$1; shift
  if [[ -t 2 ]]; then
    printf -- "\e[2Kupkg: $tpl\r" "$@" >&2
  else
    printf -- "upkg: $tpl\n" "$@" >&2
  fi
}

warning() {
  ! ${UPKG_SILENT:-false} || return 0
  local tpl=$1; shift
  if [[ -t 2 ]]; then
    printf -- "\e[2Kupkg: $tpl\n" "$@" >&2
  else
    printf -- "upkg: $tpl\n" "$@" >&2
  fi
}

fatal() {
  local tpl=$1; shift
  if [[ -t 2 ]]; then
    printf -- "\e[2Kupkg: $tpl\n" "$@" >&2
  else
    printf -- "upkg: $tpl\n" "$@" >&2
  fi
  return 1
}
