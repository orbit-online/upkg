#!/usr/bin/env bash

get_pkgname() {
  local dep=$1 upkgjson=$2 include_dep_override=$3 pkgurl pkgtype pkgname
  pkgurl=$(dep_pkgurl "$dep")
  pkgtype=$(dep_pkgtype "$dep")
  ! $include_dep_override || pkgname=$(jq -r '.name // empty' <<<"$dep")
  # Try getting the pkgname from the package itself if there is no override
  if [[ -z $pkgname ]] && ! pkgname=$(jq -re '.name // empty' <<<"$upkgjson"); then
    # pkgname has not been overridden (or override has been ignored)
    # and the package has no name included, derive one from the URL basename
    pkgname=${pkgurl%%'#'*} # Remove trailing anchor
    pkgname=${pkgname%%'?'*} # Remove query params
    pkgname=$(basename "$pkgname") # Remove path prefix
    if [[ $pkgtype = tar ]]; then
      [[ ! $pkgname =~ (\.tar(\.[^.?#/]+)?)$ ]] || pkgname=${pkgname%"${BASH_REMATCH[1]}"} # Remove .tar or .tar.* suffix
    elif [[ $pkgtype = upkg ]]; then
      [[ ! $pkgname =~ (\.upkg.json)$ ]] || pkgname=${pkgname%"${BASH_REMATCH[1]}"} # Remove .upkg.json suffix
    elif [[ $pkgtype = git ]]; then
      pkgname=${pkgname%.git} # Remove .git suffix
    fi # Don't do any suffix cleaning for plain files
  fi
  clean_pkgname "$pkgname"
}

dep_pkgtype() {
  local dep=$1
  jq -re '. |
    if has("tar") then
      "tar"
    else
      if has("zip") then
        "zip"
      else
        if has("upkg") then
          "upkg"
        else
          if has("file") then
            "file"
          else
            if has ("git") then
              "git"
            else
              empty
            end
          end
        end
      end
    end' <<<"$dep"
}

dep_pkgurl() {
  local dep=$1
  jq -re '.tar // .zip // .upkg // .file // .git // empty' <<<"$dep"
}

dep_checksum() {
  local dep=$1
  jq -re '(if has("git") then .sha1 else .sha256 end) // empty' <<<"$dep"
}

dep_is_exec() {
  local dep=$1
  jq -re 'if has("exec") then .exec else true end' <<<"$dep" >/dev/null
}

# Retrieve a dependency object index by its pkgname
get_dep_idx() {
  local pkgname=$1 dep_idx checksum
  # Use the .upkg/pkg symlink to get the .package path ...
  if ! checksum=$(readlink ".upkg/$pkgname"); then
    # package does not exist in .upkg/ return nothing
    return 0
  fi
  checksum=$(basename "$checksum")
  # ... extract the checksum from that name ...
  checksum=${checksum#*@}
  # ... and then look it up in upkg.json
  if dep_idx=$(jq -re --arg pkgname "$pkgname" --arg checksum "$checksum" '
    .dependencies | to_entries[] | select(.value.name==$pkgname and (.value.sha1==$checksum or .value.sha256==$checksum)) | .key // empty
  ' upkg.json); then # Check for name overrides first
    printf "%d\n" "$dep_idx"
  elif dep_idx=$(jq -re --arg checksum "$checksum" '
    .dependencies | to_entries[] | select((.value | has("name")==false) and (.value.sha1==$checksum or .value.sha256==$checksum)) | .key // empty
  ' upkg.json); then # No name overrides, look for matching checksum without name override
    printf "%d\n" "$dep_idx"
  fi
  # $pkgname is not present in upkg.json
}

upkg_validate_upkgjson() {
  # unique pkgname (those that are set)
  :
}
