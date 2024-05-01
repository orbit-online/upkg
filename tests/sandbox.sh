#!/usr/bin/env bash

set -Eeo pipefail
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  local shasum
  shasum=$(docker buildx build -q --file "$PKGROOT/tests/Dockerfile" --build-arg="UID=$UID" --build-arg="USER=$USER" "$PKGROOT")
  mkdir -p "$PKGROOT/sandbox"
  printf "*" > "$PKGROOT/sandbox/.gitignore"
  docker run --rm -ti --name upkg-sandbox \
    --workdir '/upkg/sandbox' \
    -v"$PKGROOT:/upkg:ro" \
    -v"$PKGROOT/sandbox:/upkg/sandbox:rw" \
    -v"${SSH_AUTH_SOCK}:/ssh_auth" \
    --entrypoint /bin/bash \
    "$shasum"
}

main "$@"
