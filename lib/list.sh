#!/usr/bin/env bash

# List all top-level installed packages. Not based on upkg.json, but the actually installed packages
upkg_list() {
  (
    if [[ ! -e .upkg ]]; then
      processing "No packages are installed in '%s'" "$PWD"
      return 0
    fi
    local dedup_path dedupdirname pkgname checksum version upkgjsonpath version
    for dedup_path in $(cd .upkg && upkg_resolve_links .); do # Don't descend into .packages, we only want the top-level
      dedupdirname=$(basename "$dedup_path")
      pkgname=${dedupdirname%@*}
      checksum=${dedupdirname#*@}
      version='no-version'
      upkgjsonpath=.upkg/$dedup_path/upkg.json
      [[ ! -e "$upkgjsonpath" ]] || version=$(jq -r '.version // "no-version"' "$upkgjsonpath")
      printf "%s\t%s\t%s\n" "$pkgname" "$version" "$checksum"
    done
  ) | (
    # Allow nice formatting if `column` (from bsdextrautils) is installed
    if type column >/dev/null 2>&1; then
      column -t -n "Packages" -N "Package name,Version,Checksum" "$@" # Forward any extra options
    else
      cat # Not installed, just output the tab/newline separated data
    fi
  )
}
