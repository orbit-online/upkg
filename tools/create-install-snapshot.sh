#!/usr/bin/env bash
# shellcheck source-path=..
set -Eeo pipefail; shopt -s inherit_errexit nullglob

PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
source "$PKGROOT/tools/common.sh"
setup_reproducible_tar

# Install the μpkg tarball globally into a tmp folder using μpkg and adjust the
# download URL, then snapshot the folder as a tarball.
main() {
  local tarball=$1 snapshot_dest=$2 tmp upkgjson
  [[ -n $tarball && -n $snapshot_dest ]] || fatal "Usage: create-install-snapshot.sh TARBALL SNAPSHOTDEST"

  # tmp root for the entire dir structure
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf \"$tmp\"" EXIT

  # Use μpkg to create the directory structure
  INSTALL_PREFIX=$tmp "$PKGROOT/bin/upkg" add -t tar -qg "$tarball"

  # Adjust the download URL of the package to point at the github release
  upkgjson=$(cat "$tmp/lib/upkg/upkg.json")
  jq --arg version "$(jq -r .version "$tmp/lib/upkg/.upkg/upkg/upkg.json")" '
    .dependencies[0].tar="https://github.com/orbit-online/upkg/releases/download/\($version)/upkg.tar.gz"
  ' <<<"$upkgjson" >"$tmp/lib/upkg/upkg.json"
  # Create the snapshot tarball
  tar \
    --sort=name \
    --mtime="@${SOURCE_DATE_EPOCH}" \
    --owner=0 --group=0 --numeric-owner \
    -caf "$snapshot_dest" -C "$tmp" \
    bin lib
}

main "$@"
