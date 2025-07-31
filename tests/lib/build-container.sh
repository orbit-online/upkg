#!/usr/bin/env bash

build_container() {
  # BASEIMG examples:
  # * debian:bookworm
  # * rockylinux:8.9
  # * fedora:41
  # * alpine:3.19
  local baseimg=${BASEIMG:-"ubuntu:22.04"}
  local tag=upkg-testing:${baseimg//:/-}
  local buildx=buildx
  type buildx &>/dev/null || buildx="docker buildx"
  $buildx build --tag "$tag" --load --file "$PKGROOT/tests/Dockerfile" --build-arg="BASEIMG=$baseimg" --build-arg="UID=$UID" --build-arg="USER=$USER" "$PKGROOT"
  printf "%s\n" "$tag"
}
