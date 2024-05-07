#!/usr/bin/env bash

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

dep_is_exec() {
  local dep=$1
  jq -re 'if has("exec") then .exec else true end' <<<"$dep" >/dev/null
}

upkg_validate_upkgjson() {
  # unique pkgname (those that are set)
  :
}
