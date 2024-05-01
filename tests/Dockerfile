FROM ubuntu:22.04
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
  wget ca-certificates git ssh jq tree netcat-openbsd bsdextrautils psmisc shellcheck && \
  rm -rf /var/lib/apt/lists/*
RUN wget -qO /tmp/delta.deb https://github.com/dandavison/delta/releases/download/0.17.0/git-delta_0.17.0_amd64.deb; \
  dpkg -i /tmp/delta.deb && rm /tmp/delta.deb

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

ARG USER
ARG UID
RUN <<EOUSERSETUP
mkdir -p /upkg/sandbox
useradd --uid "${UID}" -d /upkg/sandbox "${USER}"
adduser "$USER" sudo
EOUSERSETUP
COPY <<EOF /etc/sudoers.d/nopass
$USER ALL=(ALL) NOPASSWD:ALL
EOF
USER "$USER"
ENV PATH=/upkg/bin/:$PATH
ENV SSH_AUTH_SOCK=/ssh_auth

WORKDIR /upkg
ENTRYPOINT ["/usr/local/bin/bats"]
CMD ["tests"]
