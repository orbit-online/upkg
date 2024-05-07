#!/usr/bin/env bash

# Remove a package from upkg.json and run upkg_install
upkg_remove() {
  local pkgname=$1

  # Get the dependency object index by the checksum
  local dep_idx checksum
  # Use the .upkg/pkg symlink to get the .package path ...
  checksum=$(readlink ".upkg/$pkgname")
  checksum=$(basename "$checksum")
  # ... extract the checksum from that name ...
  checksum=${checksum#*@}
  # ... and then look it up in upkg.json
  if ! dep_idx=$(jq -re --arg pkgname "$pkgname" --arg checksum "$checksum" '
    .dependencies | to_entries[] | select(.value.name==$pkgname and (.value.sha1==$checksum or .value.sha256==$checksum)) | .key // empty
  ' "upkg.json"); then # Check for name overrides first
    if ! dep_idx=$(jq -re --arg pkgname "$pkgname" --arg checksum "$checksum" '
      .dependencies | to_entries[] | select(.value.sha1==$checksum or .value.sha256==$checksum) | .key // empty
    ' "upkg.json"); then # No name overrides, just find by checksum
      completed "'%s' is not installed" "$pkgname"
      return 0
    fi
  fi
  ! $DRY_RUN || dry_run_fail "'%s' is installed" "$pkgname"

  local upkgjson
  # .upkg might get deleted so we won't be able to copy it over later on, keep it in a var instead
  upkgjson=$(jq -r --argjson dep_idx "$dep_idx" 'del(.dependencies[$dep_idx])' upkg.json)
  # Modify upkg.json, but only in the temp dir, so a failure doesn't change anything
  printf "%s\n" "$upkgjson" >.upkg/.tmp/root/upkg.json
  upkg_install
  printf "%s\n" "$upkgjson" >upkg.json
  completed "Removed '%s'" "$pkgname"
}
