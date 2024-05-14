#!/usr/bin/env bash
# shellcheck source-path=..
set -Eeo pipefail; shopt -s inherit_errexit nullglob

PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
source "$PKGROOT/tools/common.sh"

# Run through upkg dependencies and install each one as if μpkg installed them (though in a very limited fashion)
main() {
  local pkgpath=${1:-$PKGROOT} dep pkgname archive_path dedup_path checksum tmp
  rm -rf "$pkgpath/.upkg" # clean out existing .upkg
  tmp=$(mktemp -d) # tmp for downloading the deps
  for dep in $(jq -rc '(.dependencies // [])[]' "$pkgpath/upkg.json"); do
    # Inform about limitations
    jq -re 'has("tar")' <<<"$dep" >/dev/null || fatal "Don't know how to install anything other than tarballs"
    jq -re 'if has("bin") then false else true end' <<<"$dep" >/dev/null || fatal "Don't know how to setup commands for dependencies"

    # Get the expected checksum, download the dep, and check the checksum
    checksum=$(jq -re '.sha256' <<<"$dep")
    archive_path=$tmp/$checksum
    wget -qO"$archive_path" "$(jq -r '.tar' <<<"$dep")"
    shasum -a 256 -c <(printf "%s  %s" "$checksum" "$archive_path") >/dev/null || \
      fatal "Failed to verify checksum of dependency:\n%s" "$(jq . <<<"$dep")"

    # Peek at the archive to get the pkgname
    pkgname=$(tar -xOf "$archive_path" upkg.json | jq -r .name)

    # Create package dedup destination, extract it there, and link to it from .upkg/
    dedup_path=.packages/$pkgname.tar@$checksum
    mkdir -p "$pkgpath/.upkg/$dedup_path"
    tar -xC "$pkgpath/.upkg/$dedup_path" -f "$archive_path"
    ln -s "$dedup_path" "$pkgpath/.upkg/$pkgname"
  done
}

main "$@"
