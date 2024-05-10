#!/usr/bin/env bash

# List all top-level installed packages. Not based on upkg.json, but the actually installed packages
upkg_list() {
  (
    if [[ ! -e .upkg ]]; then
      processing "No packages are installed in '%s'" "$PWD"
      return 0
    fi
    local pkgpath dedup_path dedup_dirname pkgname checksum version link_pkgname upkgjsonpath version
    for pkgpath in .upkg/*; do # Don't descend into .packages, we only want the top-level
      dedup_path=$(readlink "$pkgpath")
      dedup_dirname=$(basename "$dedup_path")
      pkgname=${dedup_dirname%@*}
      checksum=${dedup_dirname#*@}
      link_pkgname=$(basename "$pkgpath")
      version='no-version'
      upkgjsonpath=.upkg/$dedup_path/upkg.json
      if [[ -e "$upkgjsonpath" ]]; then
        pkgname=$(jq -r --arg pkgname "$pkgname" '.name // $pkgname' "$upkgjsonpath")
        version=$(jq -r --arg version "$version" '.version // $version' "$upkgjsonpath")
      fi
      printf "%s\t%s\t%s\t%s\n" "$pkgname" "$link_pkgname" "$version" "$checksum"
    done
  ) | (
    # Allow nice formatting if `column` (from bsdextrautils) is installed
    if type column >/dev/null 2>&1; then
      column -t -n "Packages" -N "Name,Link name,Version,Checksum" "$@" # Forward any extra options
    else
      cat # Not installed, just output the tab/newline separated data
    fi
  )
}
