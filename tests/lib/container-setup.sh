#!/usr/bin/env sh

main() {
  action=$1
  shift
  if [ "$action" = deps ]; then
    install_deps "$@"
  elif [ "$action" = user ]; then
    setup_user "$@"
  fi
}

install_deps() {
  baseimg=${1:?}
  case "$baseimg" in
    ubuntu:*|debian:*)
      apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates jq wget curl git \
        bzip2 xz-utils lunzip lzma lzop gzip ncompress zstd zip unzip \
        ssh tree bsdextrautils psmisc shellcheck python3 gettext openssh-server sudo parallel
      wget -qO /tmp/delta.deb https://github.com/dandavison/delta/releases/download/0.17.0/git-delta_0.17.0_amd64.deb
      dpkg -i /tmp/delta.deb
      rm /tmp/delta.deb
      ;;
    alpine:*)
      apk add \
        bash ca-certificates jq wget curl git perl-utils tar \
        bzip2 xz lzop gzip zstd zip unzip \
        openssh-client-default tree util-linux-misc psmisc shellcheck python3 gettext openssh-server sudo parallel
      wget -qO- https://github.com/dandavison/delta/releases/download/0.17.0/delta-0.17.0-x86_64-unknown-linux-musl.tar.gz | \
        tar -xz --strip-components=1 -C /usr/local/bin delta-0.17.0-x86_64-unknown-linux-musl/delta
      ;;
    *) printf "Don't know how to install deps for '%s'" "$baseimg" >&2; return 1 ;;
  esac
}

setup_user() {
  baseimg=${1:?} user=${2:?} uid=${3:?}
    mkdir -p /upkg/tests/user-home
  case "$baseimg" in
    ubuntu:*|debian:*)
      useradd --uid "$uid" -d /upkg/tests/user-home "$user"
      adduser "$user" sudo
      ;;
    alpine:*)
      adduser -u "$uid" -h /upkg/tests/user-home "$user"
      adduser "$user" sudo
      ;;
    *) printf "Don't know how to setup user for '%s'" "$baseimg" >&2; return 1 ;;
  esac
  printf "%s ALL=(ALL) NOPASSWD:ALL" "$user" /etc/sudoers.d/nopass
}

main "$@"
