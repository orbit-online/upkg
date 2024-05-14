#!/usr/bin/env bash
# shellcheck source-path=..
set -Eeo pipefail; shopt -s inherit_errexit nullglob

PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")

main() {
  local dep pkgname archive_path dedup_path checksum tmp
  rm -rf "$PKGROOT/.upkg"
  tmp=$(mktemp -d)
  for dep in $(jq -rc '(.dependencies // [])[]' "$PKGROOT/upkg.json"); do
    jq -re 'has("tar")' <<<"$dep" >/dev/null || fatal "Don't know how to install anything other than tarballs"
    checksum=$(jq -r '.sha256' <<<"$dep")
    archive_path=$tmp/$checksum
    wget -qO"$archive_path" "$(jq -r '.tar' <<<"$dep")"
    pkgname=$(tar -xOf "$archive_path" upkg.json | jq -r .name)
    dedup_path=.packages/$pkgname.tar@$checksum
    mkdir -p ".upkg/$dedup_path"
    tar -xC ".upkg/$dedup_path" -f "$archive_path"
    ln -s "$dedup_path" ".upkg/$pkgname"
  done
}

fatal() {
  local tpl=$1; shift
  printf -- "%s: $tpl\n" "$(basename "${BASH_SOURCE[0]}")" "$@" >&2
  return 1
}

main "$@"
