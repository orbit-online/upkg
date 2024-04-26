#!/usr/bin/env bash

set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(dirname "$(realpath "${BASH_SOURCE[0]}")")

main() {
  sha=$(docker buildx build -q . --file - <<EOD
FROM debian
SHELL ["/bin/bash", "-c"]

RUN <<EOR
set -e
apt-get update
apt-get install -y --no-install-recommends wget ca-certificates git ssh jq tree psmisc
ln -s /upkg/upkg.sh /usr/local/bin/upkg
EOR

ENV SSH_AUTH_SOCK=/ssh_auth
EOD
)
  mkdir "$PKGROOT/test"
  printf "*" > "$PKGROOT/test/.gitignore"
  docker run --rm -ti \
    -v"$PKGROOT/test:/test" --workdir /test \
    -v"$PKGROOT:/upkg:ro" \
    -v"${SSH_AUTH_SOCK}:/ssh_auth" \
    "$sha"
}

main "$@"
