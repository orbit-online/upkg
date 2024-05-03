#!/usr/bin/env bash

# Add a package from upkg.json (optionally determine its checksum) and run upkg_install
upkg_add() {
  local pkgtype=$1 pkgurl=$2 checksum=$3 pkgname=$4 bin=$5 exec=$6

  local archiveext
  ! [[ $pkgtype = tar ]] || archiveext=$(get_tar_suffix "$pkgurl")

  if [[ -z "$checksum" ]]; then
    # Autocalculate the checksum
    processing "No checksum given for '%s', determining now" "$pkgurl"
    if [[ $pkgtype != git ]]; then
      if [[ -e $pkgurl ]]; then
        # file exists locally on the filesystem
        checksum=$(sha256 "$pkgurl")
      else
        mkdir .upkg/.tmp/prefetched
        local tmpfile=.upkg/.tmp/prefetched/tmpfile
        upkg_fetch "$pkgurl" "$tmpfile"
        checksum=$(sha256 "$tmpfile")
        mv "$tmpfile" ".upkg/.tmp/prefetched/${checksum}${archiveext}"
      fi
    else
      # pkgurl is a git archive
      checksum=$(git ls-remote -q "$pkgurl" HEAD | grep $'\tHEAD$' | cut -f1)
    fi
  fi

  local dep={}
  dep=$(jq --arg pkgtype "$pkgtype" --arg pkgurl "$pkgurl" '.[$pkgtype]=$pkgurl' <<<"$dep")
  if [[ $pkgtype = git ]]; then dep=$(jq --arg sha1 "$checksum" '.sha1=$sha1' <<<"$dep")
  else dep=$(jq --arg sha256 "$checksum" '.sha256=$sha256' <<<"$dep"); fi
  [[ -z $pkgname ]] || dep=$(jq --arg pkgname "$pkgname" '.name=$pkgname' <<<"$dep")
  $bin || dep=$(jq '.bin=false' <<<"$dep")
  $exec || dep=$(jq '.exec=false' <<<"$dep")

  # Modify upkg.json, but only in the temp dir, so a failure doesn't change anything
  local upkgjson={}
  [[ ! -e upkg.json ]] || upkgjson=$(cat upkg.json)
  jq --argjson dep "$dep" '.dependencies+=[$dep]' <<<"$upkgjson" >.upkg/.tmp/root/upkg.json
  upkg_install
  cp .upkg/.tmp/root/upkg.json upkg.json

  processing "Added '%s'" "$pkgurl"
}
