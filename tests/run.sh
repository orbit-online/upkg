#!/usr/bin/env bash
# shellcheck source-path=..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

source "$PKGROOT/tests/lib/build-container.sh"

main() {
  local tag
  tag=$(build_container)
  local docker_opts=()
  if [[ -t 0 || -t 1 ]]; then
    docker_opts+=(-ti)
  else
    docker_opts+=( -a stdout -a stderr)
  fi
  mkdir -p "$PKGROOT/tests/bats-tmp"
  exec docker run --rm "${docker_opts[@]}" \
    --name "upkg-tests-${tag//:/-}" \
    -eUPDATE_SNAPSHOTS -eRESTRICT_BIN \
    -eTMPDIR=/upkg/tests/bats-tmp \
    -v"$PKGROOT:/upkg:ro" \
    -v"$PKGROOT/tests:/upkg/tests:rw" \
    -v"$PKGROOT/tests/bats-tmp:/upkg/tests/bats-tmp:rw" \
    "$tag" "$@"
}

main "$@"
