#!/usr/bin/env bash
# shellcheck source-path=..
set -Eeo pipefail; shopt -s inherit_errexit nullglob

PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
source "$PKGROOT/tools/common.sh"
source "$PKGROOT/lib/compat.sh"
setup_reproducible_tar

# Adjust upkg.json of upkg-compat so it includes a dependency on the given UPKGTARBALL
# then bundle a tarball for updates, then install it globally into a tmp folder and
# snapshot the folder as a tarball.
main() {
  local upkg_tarball tarball_dest snapshot_dest tmp tmp_pkg tmp_snapshot version upkgjson old_checksum new_checksum
  [[ -n $1 && -n $2 && -n $3 ]] || fatal "Usage: create-compat-package.sh UPKGTARBALL TARBALLDEST SNAPSHOTDEST"
  upkg_tarball=$(realpath "$1")
  tarball_dest=$(realpath "$(dirname "$2")")/$(basename "$2")
  snapshot_dest=$(realpath "$(dirname "$3")")/$(basename "$3")

  # tmp root for the package creation and also the global install dir structure
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf \"$tmp\"" EXIT
  tmp_pkg=$tmp/pkg
  tmp_snapshot=$tmp/snapshot
  mkdir "$tmp_pkg" "$tmp_snapshot"

  cp -R "$PKGROOT/compat/upkg.json" "$PKGROOT/compat/bin" "$PKGROOT/compat/README.md" "$PKGROOT/LICENSE" "$tmp_pkg"
  # Copy the version from UPKGTARBALL to upkg-compat
  version=$(tar -xOf "$upkg_tarball" upkg.json | jq -re .version)
  (
    cd "$tmp_pkg"
    # Depend on new μpkg
    "$PKGROOT/bin/upkg" add -qBp upkg-new "$upkg_tarball"
    # Bundle for global snapshot install
    "$PKGROOT/bin/upkg" bundle -d "$tmp/upkg-compat-global.tar" -V "$version" bin README.md LICENSE
    # Adjust the URL for actual bundling
    # shellcheck disable=SC2030
    upkgjson=$(cat "$tmp_pkg/upkg.json")
    jq --arg version "$version" '
      . as $root |
      .dependencies | to_entries[] | select(.value.name=="upkg-new") | .key as $idx |
      $root | .dependencies[$idx].tar="https://github.com/orbit-online/upkg/releases/download/\($version)/upkg.tar.gz"
    ' <<<"$upkgjson" >"$tmp_pkg/upkg.json"
    # Create upkg-compat bundle
    "$PKGROOT/bin/upkg" bundle -d "$tarball_dest" -V "$version" bin README.md LICENSE
  )
  # Create a global installation in tmp
  INSTALL_PREFIX=$tmp_snapshot "$PKGROOT/bin/upkg" add -qg "$tmp/upkg-compat-global.tar"
  # Extract upkg.json from the bundle where both the URL is adjusted and the version is set
  tar -xOf "$tarball_dest" upkg.json >"$tmp_snapshot/lib/upkg/.upkg/upkg-compat/upkg.json"
  # Adjust the URL and also the checksum for the upkg-compat tarball
  new_checksum=$(sha256 "$tarball_dest" | cut -d ' ' -f1)
  upkgjson=$(cat "$tmp_snapshot/lib/upkg/upkg.json")
  jq --arg version "$version" --arg checksum "$new_checksum" '
    .dependencies[0].tar="https://github.com/orbit-online/upkg/releases/download/\($version)/upkg-compat.tar.gz" |
    .dependencies[0].sha256=$checksum
  ' <<<"$upkgjson" >"$tmp_snapshot/lib/upkg/upkg.json"
  # Fix the checksum paths for upkg-compat so they match the checksum
  old_checksum=$(sha256 "$tmp/upkg-compat-global.tar" | cut -d ' ' -f1)
  mv "$tmp_snapshot/lib/upkg/.upkg/.packages/upkg-compat.tar@$old_checksum" "$tmp_snapshot/lib/upkg/.upkg/.packages/upkg-compat.tar@$new_checksum"
  _ln_sTf "../.packages/upkg-compat.tar@$new_checksum/bin/upkg" "$tmp_snapshot/lib/upkg/.upkg/.bin/upkg"
  _ln_sTf ".packages/upkg-compat.tar@$new_checksum" "$tmp_snapshot/lib/upkg/.upkg/upkg-compat"
  # Create the snapshot tarball
  _tar \
    --sort=name \
    --mode='u+rwX,g-w,o-w' \
    --mtime="@${SOURCE_DATE_EPOCH}" \
    --owner=0 --group=0 --numeric-owner \
    -caf "$snapshot_dest" -C "$tmp_snapshot" \
    bin lib
}

main "$@"

