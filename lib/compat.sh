#!/usr/bin/env bash

if (ln --help 2>&1 || true) | grep -q 'GNU coreutils\|BusyBox'; then
  _ln_sT() {
    ln -sT "$@"
  }
  _ln_sTf() {
    ln -sTf "$@"
  }
else
  _ln_sT() {
    # shellcheck disable=SC2217
    ln -sFi "$@" <<<'n'
  }
  _ln_sTf() {
    ln -sFf "$@"
  }
fi

SHASUM=sha256sum
type sha256sum &>/dev/null || SHASUM="shasum -a 256"
sha256() {
  local filepath=$1 sha256=$2
  if [[ -n $sha256 ]]; then
    $SHASUM -c <(printf "%s  %s" "$sha256" "$filepath") >/dev/null
  else
    $SHASUM "$filepath" | cut -d ' ' -f1
  fi
}
