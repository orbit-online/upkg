#!/usr/bin/env bash
# shellcheck source-path=..
set -Eeo pipefail; shopt -s inherit_errexit nullglob

PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
source "$PKGROOT/tools/common.sh"

# Create the install tarball and then the install snapshot tarball.
# Output the sha256 of the latter
main() {
  local version=$1 tarball snapshot_dest
  [[ -n $version ]] || fatal "Usage: create-install-snapshot-sha256.sh VERSION"
  tarball=$(mktemp --suffix .tar.gz)
  snapshot_dest=$(mktemp --suffix .tar.gz)
  # shellcheck disable=SC2064
  trap "rm \"$tarball\" \"$snapshot_dest\"" EXIT
  # Don't include the README, it will contain the shasum of the bundle we are creating right now
  (cd "$PKGROOT"; "$PKGROOT/bin/upkg" bundle -qd "$tarball" -V "$version" bin lib LICENSE upkg.schema.json)
  "$PKGROOT/tools/create-install-snapshot.sh" "$tarball" "$snapshot_dest"
  shasum -a 256 "$snapshot_dest" | cut -d ' ' -f1
}

main "$@"
