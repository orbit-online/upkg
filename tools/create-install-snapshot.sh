#!/usr/bin/env bash
# shellcheck source-path=..
set -Eeo pipefail; shopt -s inherit_errexit nullglob

PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
source "$PKGROOT/tools/common.sh"
setup_reproducible_tar

# Install the μpkg package using μpkg into a tmp folder and adjust the download URL
# then archive it all into a snapshot tarball
main() {
  local archive_path=$1 dest=$2 tmp upkgjson
  [[ -n $archive_path && -n $dest ]] || fatal "Usage: create-install-snapshot.sh ARCHIVEPATH DEST"

  # tmp root for the entire dir structure
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf \"$tmp\"" EXIT

  # Use μpkg to create the directory structure
  INSTALL_PREFIX=$tmp "$PKGROOT/bin/upkg" add -qg "$(realpath "$archive_path")"

  upkgjson=$(cat "$tmp/lib/upkg/upkg.json")
  jq --arg version "$(jq -r .version "$tmp/lib/upkg/.upkg/upkg/upkg.json")" '
    .dependencies[0].tar="https://github.com/orbit-online/upkg/releases/download/\($version)/upkg.tar.gz"
  ' <<<"$upkgjson" >"$tmp/lib/upkg/upkg.json"
  tar \
    --sort=name \
    --mtime="@${SOURCE_DATE_EPOCH}" \
    --owner=0 --group=0 --numeric-owner \
    -caf "$dest" -C "$tmp" \
    bin lib
}

main "$@"
