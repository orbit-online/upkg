#!/usr/bin/env bash

# Returns a dependency object
upkg_get_dep_idx() {
  local pkgpath=$1 pkgname=$2 checksum
  [[ -e "$pkgpath/.upkg/$pkgname" ]] || fatal "Unable to find '%s' in '%s'" "$pkgname" "$pkgpath/.upkg"
  # Use the .upkg/pkg symlink to get the .package path ...
  checksum=$(readlink "$pkgpath/.upkg/$pkgname")
  checksum=$(basename "$checksum")
  # ... extract the checksum from that name ...
  checksum=${checksum#*@}
  # ... and then look it up in upkg.json
  if ! jq -re --arg pkgname "$pkgname" --arg checksum "$checksum" '
    .dependencies | to_entries[] | select(.value.name==$pkgname and (.value.sha1==$checksum or .value.sha256==$checksum)) | .key // empty
  ' "$pkgpath/upkg.json"; then # Check for name overrides first
    if ! jq -re --arg pkgname "$pkgname" --arg checksum "$checksum" '
      .dependencies | to_entries[] | select(.value.sha1==$checksum or .value.sha256==$checksum) | .key // empty
    ' "$pkgpath/upkg.json"; then # No name overrides, just find by checksum
      fatal "'%s' is not installed" "$pkgname"
    fi
  fi
}

dep_pkgtype() {
  local dep=$1
  jq -re '. |
    if has("file") then
      "file"
    else
      if has("tar") then
        "tar"
      else
        if has ("git") then
          "git"
        else
          empty
        end
      end
    end' <<<"$dep"
}

dep_pkgurl() {
  local dep=$1
  jq -re '.file // .tar // .git // empty' <<<"$dep"
}

dep_checksum() {
  local dep=$1
  jq -re '(if has("git") then .sha1 else .sha256 end) // empty' <<<"$dep"
}

dep_name() {
  local dep=$1 pkgname
  pkgname="$(jq -re '.name // empty' <<<"$dep")" || return 1
  clean_pkgname "$pkgname"
}

# Whether the dependency should be linked to .upkg/.bin/
dep_bin() {
  local dep=$1
  jq -r '(.bin // [])[]' <<<"$dep" >/dev/null
}

# Whether the dependency should be executable
dep_exec() {
  local dep=$1
  jq -re '.exec // true' <<<"$dep" >/dev/null
}

upkg_validate_upkgjson() {
  # unique pkgname (those that are set)
  :
}
