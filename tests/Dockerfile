FROM ubuntu:22.04
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
  ca-certificates jq wget curl git \
  bzip2 xz-utils lunzip lzma lzop gzip ncompress zstd \
  ssh tree bsdextrautils psmisc shellcheck python3 gettext openssh-server sudo parallel && \
  rm -rf /var/lib/apt/lists/*
RUN wget -qO /tmp/delta.deb https://github.com/dandavison/delta/releases/download/0.17.0/git-delta_0.17.0_amd64.deb; \
  dpkg -i /tmp/delta.deb && rm /tmp/delta.deb

WORKDIR /usr/lib/bats
RUN <<EOINSTALL
wget -qO- https://github.com/bats-core/bats-core/archive/refs/tags/v1.11.0.tar.gz | tar xz --strip-components 1
./install.sh /usr/local
mkdir bats-support bats-assert bats-file
wget -qO- https://github.com/bats-core/bats-support/archive/refs/tags/v0.3.0.tar.gz | tar xzC bats-support --strip-components 1
wget -qO- https://github.com/bats-core/bats-assert/archive/refs/tags/v2.1.0.tar.gz | tar xzC bats-assert --strip-components 1
wget -qO- https://github.com/bats-core/bats-file/archive/refs/tags/v0.4.0.tar.gz | tar xzC bats-file --strip-components 1
EOINSTALL

RUN mkdir /restricted
COPY tests/lib/setup-upkg-path-wrapper.sh /restricted/
RUN /restricted/setup-upkg-path-wrapper.sh /upkg/bin/upkg /restricted

ARG USER
ARG UID
RUN <<EOUSERSETUP
mkdir -p /upkg/tests/user-home
useradd --uid "$UID" -d /upkg/tests/user-home "$USER"
adduser "$USER" sudo
EOUSERSETUP
COPY <<EOF /etc/sudoers.d/nopass
$USER ALL=(ALL) NOPASSWD:ALL
EOF
USER $USER
ENV USER=$USER
ENV PATH=/restricted/upkg-wrapper-bin:$PATH

WORKDIR /upkg
ENTRYPOINT ["/usr/local/bin/bats"]
CMD ["tests"]
