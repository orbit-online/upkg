#!/usr/bin/env bash
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  local shasum
  shasum=$(docker buildx build -q --file "$PKGROOT/tests/Dockerfile" --build-arg="UID=$UID" --build-arg="USER=$USER" "$PKGROOT")
  mkdir -p "$PKGROOT/sandbox"
  printf "*" > "$PKGROOT/sandbox/.gitignore"
  if [[ $(docker container inspect -f '{{.State.Running}}' upkg-sandbox 2>/dev/null) = "true" ]]; then
    printf "sandbox.sh: upkg-sandbox already running, using docker exec instead\n" >&2
    exec docker exec -ti upkg-sandbox /bin/bash
  else
    exec docker run --rm -ti --name upkg-sandbox \
      --workdir '/upkg/sandbox' \
      -v"$PKGROOT:/upkg:ro" \
      -v"$PKGROOT/sandbox:/upkg/sandbox:rw" \
      -v"${SSH_AUTH_SOCK}:/ssh_auth" \
      --entrypoint /bin/bash \
      "$shasum"
  fi
}

main "$@"
