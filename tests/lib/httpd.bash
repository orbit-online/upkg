#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit nullglob

# Setup HTTP server to serve package fixtures
setup_package_fixtures_httpd() {
  export HTTPD_ROOT=$BATS_TEST_TMPDIR/httpd/root
  mkdir -p "$HTTPD_ROOT"
  (cd "$PACKAGE_FIXTURES"; close_non_std_fds; exec "$PYTHON" -u -m http.server -b '127.0.0.1' 0 >"$HTTPD_ROOT/log" 2>&1) &
  printf "%d" "$!" >"$HTTPD_ROOT/pid"

  local log_line wait_timeout=1000
  # shellcheck disable=SC2094
  while ((wait_timeout-- > 0)); do
    sleep .01
    [[ -e "$HTTPD_ROOT/log" ]] || continue
    while read -r -d $'\n' log_line; do
      if [[ $log_line =~ \((http:\/\/[^\)]+)\/\) ]]; then
        export HTTPD_PKG_FIXTURES_ADDR=${BASH_REMATCH[1]}
        true >"$HTTPD_ROOT/log" # Clear log before returning
        return 0
      fi
    done <"$HTTPD_ROOT/log"
    if ! kill -0 "$(cat "$HTTPD_ROOT/pid")"; then
      fail "The HTTP server crashed during startup (use \"--filter-tags '!http'\" to skip HTTP tests): $(cat "$HTTPD_ROOT/log")."
    fi
  done
  kill -INT "$(cat "$HTTPD_ROOT/pid")" 2>/dev/null
  fail "Timed out waiting for the HTTP server to output listening port log lines (use \"--filter-tags '!http'\" to skip HTTP tests): %s." "$(cat "$HTTPD_ROOT/log")"
}

teardown_package_fixtures_httpd() {
  local httpd_pid
  httpd_pid=$(cat "$HTTPD_ROOT/pid")
  printf -- "-- httpd logs --\n" >&2
  cat "$HTTPD_ROOT/log" >&2
  printf -- "-- httpd logs --\n" >&2
  kill -INT "$httpd_pid" 2>/dev/null
  wait "$httpd_pid" || printf "HTTP server exited with status code %d\n" "$?" >&2
}
