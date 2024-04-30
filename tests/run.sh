#!/usr/bin/env bash

set -Eeo pipefail
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  local shasum
  shasum=$(docker buildx build -q "$PKGROOT" --tag upkg-tests --file - <<EOD
FROM ubuntu:22.04
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \\
  wget ca-certificates git ssh jq tree netcat-openbsd bsdextrautils diffutils
RUN wget -qO /tmp/delta.deb https://github.com/dandavison/delta/releases/download/0.17.0/git-delta_0.17.0_amd64.deb; \\
  dpkg -i /tmp/delta.deb

WORKDIR /usr/local/bats
RUN <<EOINSTALL
wget -qO- https://github.com/bats-core/bats-core/archive/refs/tags/v1.11.0.tar.gz | tar xz --strip-components 1
./install.sh /usr/local
cd lib
mkdir bats-support bats-assert bats-file
wget -qO- https://github.com/bats-core/bats-support/archive/refs/tags/v0.3.0.tar.gz | tar xzC bats-support --strip-components 1
wget -qO- https://github.com/bats-core/bats-assert/archive/refs/tags/v2.1.0.tar.gz | tar xzC bats-assert --strip-components 1
wget -qO- https://github.com/bats-core/bats-file/archive/refs/tags/v0.4.0.tar.gz | tar xzC bats-file --strip-components 1
EOINSTALL

ENV BATS_LIB_PATH=/usr/local/bats/lib

WORKDIR /upkg
ENTRYPOINT ["/usr/local/bin/bats"]
CMD ["tests"]
EOD
  )
  if [[ -t 0 || -t 1 ]]; then
    exec docker run --rm -ti -eUPDATE_SNAPSHOTS -v"$PKGROOT:/upkg:ro" "$shasum" "$@"
  else
    exec docker run --rm -a stdout -a stderr -eUPDATE_SNAPSHOTS -v"$PKGROOT:/upkg:ro" "$shasum" "$@"
  fi
}

main "$@"
