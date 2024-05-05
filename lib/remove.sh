#!/usr/bin/env bash

# Remove a package from upkg.json and run upkg_install
upkg_remove() {
  local pkgname=$1 dep_idx upkg_json
  dep_idx=$(upkg_get_dep_idx . "$pkgname")
  # .upkg might get deleted so we won't be able to copy it over later on, keep it in a var instead
  upkg_json=$(jq -r --argjson dep_idx "$dep_idx" 'del(.dependencies[$dep_idx])' upkg.json)
  # Modify upkg.json, but only in the temp dir, so a failure doesn't change anything
  printf "%s\n" "$upkg_json" >.upkg/.tmp/root/upkg.json
  upkg_install
  printf "%s\n" "$upkg_json" >upkg.json
  processing "Removed '%s'" "$pkgname"
}
