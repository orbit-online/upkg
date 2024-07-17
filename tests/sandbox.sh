#!/usr/bin/env bash
# shellcheck source-path=..
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

source "$PKGROOT/tests/lib/build-container.sh"

main() {
  local tag
  tag=$(build_container)
  mkdir -p "$PKGROOT/tests/user-home"
  if [[ $(docker container inspect -f '{{.State.Running}}' upkg-sandbox 2>/dev/null) = "true" ]]; then
    printf "sandbox.sh: upkg-sandbox already running, using docker exec instead\n" >&2
    exec docker exec -ti upkg-sandbox /bin/bash
  else
    exec docker run --rm -ti --name upkg-sandbox \
      --workdir '/upkg/tests/user-home' \
      -v"$PKGROOT:/upkg:ro" \
      -v"$PKGROOT/tests/user-home:/upkg/tests/user-home:rw" \
      -eSSH_AUTH_SOCK=/ssh_auth_sock \
      -v"${SSH_AUTH_SOCK}:/ssh_auth_sock" \
      --entrypoint /bin/bash \
      "$tag"
  fi
}

main "$@"
