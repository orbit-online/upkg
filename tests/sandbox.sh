#!/usr/bin/env bash

set -Eeo pipefail
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  docker buildx build "$PKGROOT" --tag upkg-sandbox --file - <<EOD
FROM ubuntu:22.04
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \\
  wget ca-certificates git ssh jq tree netcat-openbsd bsdextrautils diffutils
RUN wget -qO /tmp/delta.deb https://github.com/dandavison/delta/releases/download/0.17.0/git-delta_0.17.0_amd64.deb; \\
  dpkg -i /tmp/delta.deb

WORKDIR /upkg/sandbox
RUN useradd --uid "$UID" -d /upkg/sandbox "$USER"
RUN adduser "$USER" sudo
COPY <<EOF /etc/sudoers.d/nopass
$USER ALL=(ALL) NOPASSWD:ALL
EOF
ENV PATH=\$PATH/upkg/bin
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
