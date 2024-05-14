#!/usr/bin/env bash
# shellcheck source-path=..
set -Eeo pipefail; shopt -s inherit_errexit nullglob

PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
source "$PKGROOT/tools/common.sh"
setup_reproducible_tar

# Create μpkg package of μpkg
main() {
  local version=$1 dest=$2 pkgpath=${3:-$PKGROOT}
  [[ -n $version && -n $dest ]] || fatal "Usage: create-package.sh VERSION DEST [PKGPATH]"

  # Set the version in upkg.json, revert it when we are done
  # The variable is global so we can refer to it in the trap, preventing keys like $schema from being interpolated
  UPKGJSON=$(cat "$pkgpath/upkg.json")
  # shellcheck disable=SC2064
  trap "printf \"%s\n\" \"\$UPKGJSON\" >\"$pkgpath/upkg.json\"" EXIT
  jq --arg version "$version" '.version=$version' <<<"$UPKGJSON" >upkg.json

  # Create the archive
  tar \
    --sort=name \
    --mode='u+rwX,g-w,o-w' \
    --mtime="@${SOURCE_DATE_EPOCH}" \
    --owner=0 --group=0 --numeric-owner \
    -caf "$dest" -C "$pkgpath" \
    bin lib LICENSE README.md upkg.json upkg.schema.json
}

main "$@"
