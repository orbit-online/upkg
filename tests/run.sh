#!/usr/bin/env bash

set -Eeo pipefail
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  local shasum
  shasum=$(docker buildx build -q --file "$PKGROOT/tests/Dockerfile" --build-arg="UID=$UID" --build-arg="USER=$USER" "$PKGROOT")
  local mode=ro docker_opts=()
  ! ${UPDATE_SNAPSHOTS:-false} || mode=rw
  ! ${CREATE_SNAPSHOTS:-false} || mode=rw
  if [[ -t 0 || -t 1 ]]; then
    docker_opts+=(-ti)
  else
    docker_opts+=( -a stdout -a stderr)
  fi
  exec docker run --rm "${docker_opts[@]}" \
    --name upkg-tests \
    -eUPDATE_SNAPSHOTS -eCREATE_SNAPSHOTS \
    -v"$PKGROOT:/upkg:$mode" \
    "$shasum" "$@"
}

main "$@"
