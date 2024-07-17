ARG BASEIMG
FROM $BASEIMG
ARG BASEIMG
COPY --chmod=0755 tests/lib/setup-container.sh /setup-container.sh
RUN /setup-container.sh deps $BASEIMG
SHELL ["/bin/bash", "-Eeo", "pipefail", "-c"]

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
RUN /setup-container.sh user $BASEIMG $USER $UID
RUN mkdir /sshd; chown $UID:$UID /sshd
ENV SSHD_BASE=/sshd
USER $USER
ENV USER=$USER
ENV PATH=/restricted/upkg-wrapper-bin:$PATH

WORKDIR /upkg
ENTRYPOINT ["/usr/local/bin/bats"]
CMD ["tests"]
