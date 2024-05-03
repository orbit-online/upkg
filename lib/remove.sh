#!/usr/bin/env bash

# Remove a package from upkg.json and run upkg_install
upkg_remove() {
  local pkgname=$1 dep_idx
  dep_idx=$(upkg_get_dep_idx . "$pkgname")
  # Modify upkg.json, but only in the temp dir, so a failure doesn't change anything
  jq -r --arg dep_idx "$dep_idx" 'del(.dependencies[$dep_idx])' upkg.json >.upkg/.tmp/root/upkg.json
  upkg_install
  cp .upkg/.tmp/root/upkg.json upkg.json
  processing "Removed '%s'" "$pkgname"
}
