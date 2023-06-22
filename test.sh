#!/usr/bin/env bash

set -eo pipefail
PKGROOT=$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"; echo "$PWD")

main() {
  sha=$(docker buildx build -q . --file - <<EOD
FROM debian
SHELL ["/bin/bash", "-c"]

RUN <<EOR
set -e
apt-get update
apt-get install -y --no-install-recommends wget ca-certificates git ssh jq tree
ln -s /usr/local/upkg/upkg/upkg.sh /usr/local/bin/upkg
EOR

ENV SSH_AUTH_SOCK=/ssh_auth
EOD
)
  docker run --rm -ti -v"$PKGROOT:/usr/local/upkg/upkg" -v"${SSH_AUTH_SOCK}:/ssh_auth" "$sha"
}

main "$@"