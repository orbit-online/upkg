#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit nullglob

# Setup SSH server to serve git package fixtures
setup_package_fixtures_sshd() {
  export SSHD_ROOT
  if [[ -n $SSHD_BASE ]]; then
    SSHD_ROOT=$SSHD_BASE/${BATS_TEST_TMPDIR#'/'}
  else
    SSHD_ROOT=$BATS_TEST_TMPDIR/sshd/root
  fi
  local sshd_port log_line wait_timeout=1000
  mkdir -p "$SSHD_ROOT"
  sshd_port=$("$PYTHON" -c 'import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.bind(("", 0))
addr = s.getsockname()
print(addr[1])
s.close()')
  SSHD_PORT=$sshd_port envsubst <"$BATS_TEST_DIRNAME/assets/sshd_config" >"$SSHD_ROOT/sshd_config"
  ssh-keygen -q -N '' -t ed25519 -f "$SSHD_ROOT/ssh_host_ed25519"
  ssh-keygen -q -N '' -t ed25519 -f "$SSHD_ROOT/ssh_client_ed25519"
  # shellcheck disable=SC2094
  (cd "$SSHD_ROOT"; close_non_std_fds; exec $SSHD -D -E "$SSHD_ROOT/log" -f "$SSHD_ROOT/sshd_config" &>"$SSHD_ROOT/log") &
  # shellcheck disable=SC2094
  while ((wait_timeout-- > 0)); do
    sleep .01
    [[ -e "$SSHD_ROOT/log" ]] || continue
    while read -r -d $'\n' log_line; do
      if [[ $log_line =~ Server\ listening\ on\ ([^ ]+)\ port\ ([0-9]+)\. ]]; then
        SSHD_PKG_FIXTURES_HOST=${BASH_REMATCH[1]} SSHD_PKG_FIXTURES_PORT=${BASH_REMATCH[2]} \
          envsubst <"$BATS_TEST_DIRNAME/assets/ssh_config" >"$SSHD_ROOT/ssh_config"
        true >"$SSHD_ROOT/log"
        chmod -R go-rwx "$SSHD_ROOT"
        export GIT_SSH_COMMAND
        GIT_SSH_COMMAND="ssh -F $(printf "%q" "$SSHD_ROOT/ssh_config")"
        return 0
      fi
      if [[ -e "$SSHD_ROOT/pid" ]] && ! kill -0 "$(cat "$SSHD_ROOT/pid")"; then
        fail "The SSH server crashed during startup (use \"--filter-tags '!ssh'\" to skip SSH tests): $(cat "$SSHD_ROOT/log")."
      fi
    done <"$SSHD_ROOT/log"
  done
  kill -INT "$(cat "$SSHD_ROOT/pid")" 2>/dev/null
  fail "Timed out waiting for the SSH server to output listening port log lines (use \"--filter-tags '!ssh'\" to skip SSH tests): %s." "$(cat "$SSHD_ROOT/log")"
}

teardown_package_fixtures_sshd() {
  local sshd_pid
  sshd_pid=$(cat "$SSHD_ROOT/pid")
  printf -- "-- sshd logs --\n" >&2
  cat "$SSHD_ROOT/log" >&2
  printf -- "-- sshd logs --\n" >&2
  kill -INT "$sshd_pid" 2>/dev/null
  wait "$sshd_pid" || printf "SSH server exited with status code %d\n" "$?" >&2
}
