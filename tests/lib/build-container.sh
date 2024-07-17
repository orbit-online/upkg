#!/usr/bin/env bash

build_container() {
  # BASEIMG examples:
  # * debian:bookworm
  # * rockylinux:8.9
  # * fedora:41
  # * alpin:3.19
  local baseimg=${BASEIMG:-"ubuntu:22.04"}
  local tag=upkg-testing:${baseimg//:/-}
  docker buildx build --tag "$tag" --file "$PKGROOT/tests/Dockerfile" --build-arg="BASEIMG=$baseimg" --build-arg="UID=$UID" --build-arg="USER=$USER" "$PKGROOT"
  printf "%s\n" "$tag"
}
