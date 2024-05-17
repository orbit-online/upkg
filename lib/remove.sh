#!/usr/bin/env bash

# Remove a package from upkg.json and run upkg_install
upkg_remove() {
  local pkgname=$1 dep_idx
  dep_idx=$(get_dep_idx "$pkgname")
  if [[ -z $dep_idx ]]; then
    completed "'%s' is not installed" "$pkgname"
    return 0
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
