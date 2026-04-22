#!/usr/bin/env bash

# List all top-level installed packages. Not based on upkg.json, but the actually installed packages
upkg_list() {
  local json=$1
  shift
  (
    if [[ ! -e .upkg ]]; then
      processing "No packages are installed in '%s'" "$PWD"
      return 0
    fi
    local pkgpath dedup_dirname upkgjson
    for pkgpath in .upkg/*; do # Don't descend into .packages, we only want the top-level
      dedup_path=$(readlink "$pkgpath")
      dedup_dirname=$(basename "$dedup_path")
      upkgjson=$(cat ".upkg/$dedup_path/upkg.json" 2>/dev/null || printf '{}')
      jq \
        --arg pkgname "${dedup_dirname%@*}" \
        --arg linkPkgName "$(basename "$pkgpath")" \
        --arg checksum "${dedup_dirname#*@}" \
       '{
        "Name": (.name // $pkgname),
        "Link name": $linkPkgName,
        "Version": (.version // "no-version"),
        "Checksum": $checksum,
      }' <<<"$upkgjson"
    done
  ) | (
    if $json; then
      jq -s '{"Packages": .}'
    else
      if [[ $# -gt 0 ]]; then
        type column &>/dev/null || fatal "\`column\` is not installed, unable to forward options"
        warning "Usage of COLUMNOPTS is deprecated, use the --json option and pipe it to \`jq -r '.packages[] | join(\"\\\\t\")' | column\` instead"
        jq -rs '.[] | join("\t")' | column -t -n "Packages" -N "Name,Link name,Version,Checksum" "$@" # Forward any extra options
      else
        jq -rs '.[] | join("\t")' | (
          column -t -n "Packages" -N "Name,Link name,Version,Checksum" 2>/dev/null || {
            printf "Name\tLink name\tVersion\tChecksum\n"; cat;
          }
        )
      fi
    fi
  )
}
