#!/usr/bin/env bash

set -Eeo pipefail
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  docker buildx build "$PKGROOT" --tag upkg-sandbox --file - <<EOD
FROM debian
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \\
  wget ca-certificates git ssh jq tree psmisc sudo
RUN ln -s /upkg/bin/upkg /usr/local/bin/upkg
WORKDIR /upkg/sandbox
RUN useradd --uid "$UID" -d /upkg/sandbox "$USER"
RUN adduser "$USER" sudo
COPY <<EOF /etc/sudoers.d/nopass
$USER ALL=(ALL) NOPASSWD:ALL
EOF
ENV SSH_AUTH_SOCK=/ssh_auth
EOD
  mkdir -p "$PKGROOT/sandbox"
  printf "*" > "$PKGROOT/sandbox/.gitignore"
  docker run --rm -ti \
    --user "$USER" \
    -v"$PKGROOT:/upkg:ro" \
    -v"$PKGROOT/sandbox:/upkg/sandbox:rw" \
    -v"${SSH_AUTH_SOCK}:/ssh_auth" \
    upkg-sandbox
}

main "$@"
