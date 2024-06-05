#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  local baseimg=${BASEIMG:-"ubuntu:22.04"}
  local tag=upkg-testing:${baseimg//:/-}
  docker buildx build --tag "$tag" --file "$PKGROOT/tests/Dockerfile" --build-arg="BASEIMG=$baseimg" --build-arg="UID=$UID" --build-arg="USER=$USER" "$PKGROOT"
  local mode=ro docker_opts=()
  ! ${UPDATE_SNAPSHOTS:-false} || mode=rw
  ! ${CREATE_SNAPSHOTS:-false} || mode=rw
  if [[ -t 0 || -t 1 ]]; then
    docker_opts+=(-ti)
  else
    docker_opts+=( -a stdout -a stderr)
  fi
  mkdir -p "$PKGROOT/tests/bats-tmp"
  exec docker run --rm "${docker_opts[@]}" \
    --name "upkg-tests-${baseimg//:/-}" \
    -eUPDATE_SNAPSHOTS -eCREATE_SNAPSHOTS -eRESTRICT_BIN \
    -eTMPDIR=/upkg/tests/bats-tmp \
    -v"$PKGROOT:/upkg:ro" \
    -v"$PKGROOT/tests:/upkg/tests:$mode" \
    -v"$PKGROOT/tests/bats-tmp:/upkg/tests/bats-tmp:rw" \
    "$tag" "$@"
}

main "$@"
