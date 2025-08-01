#!/usr/bin/env bash

upkg_bundle() {
  # See https://reproducible-builds.org/docs/archives/ for more info on the weird tar parameters
  local version=$1 dest=$2 pkgname=$3 tarout
  shift 3
  local paths=("$@")
  local upkgjson={}
  [[ ! -e upkg.json ]] || upkgjson=$(cat upkg.json)

  if [[ ${#paths[@]} -eq 0 ]]; then
    if jq -re 'has("bin")' <<<"$upkgjson" >/dev/null; then
      readarray -t -d $'\n' paths < <(jq -r '.bin[]' <<<"$upkgjson")
    elif [[ -e bin ]]; then
      paths=(bin)
    else
      fatal "No paths specified, \"bin\" is not set in upkg.json, and default \"bin/\" path does not exist. There are no files to create a package from."
    fi
    local opt_path
    ! opt_path=$(compgen -G "LICENSE*") || paths+=("${opt_path%%$'\n'*}")
    ! opt_path=$(compgen -G "README*") || paths+=("${opt_path%%$'\n'*}")
  fi

  [[ -z $version ]] || upkgjson=$(jq --arg version "$version" '.version=$version' <<<"$upkgjson")
  [[ -z $pkgname ]] || upkgjson=$(jq --arg pkgname "$pkgname" '.name=$pkgname' <<<"$upkgjson")
  # tmpfile for upkg.json so we can set the version without modifying the original
  printf "%s\n" "$upkgjson" >.upkg/.tmp/upkg.json

  # LC_ALL=C: Ensure stable file sorting
  # POSIXLY_CORRECT: Don't include atime & ctime in tar archives
  local source_date_epoch=1704067200 # Fixed timestamp for reproducible builds. 2024-01-01T00:00:00Z
  # Create the archive
  # Set the version in upkg.json by redirecting jq output
  if ! tarout=$(unset POSIXLY_CORRECT; LC_ALL=C _tar \
    --sort=name \
    --mode='u+rwX,g-w,o-w' \
    --mtime="@${source_date_epoch}" \
    --owner=0 --group=0 --numeric-owner \
    --transform="s#\.upkg/\.tmp/upkg\.json#upkg.json#" \
    -cvaf "$dest" "${paths[@]}" .upkg/.tmp/upkg.json 2>&1); then
    rm -f "$dest"
    fatal "Failed to bundle. tar output:\n%s" "$tarout"
  fi
}
