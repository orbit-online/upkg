#!/usr/bin/env bash

# Add a package from upkg.json (optionally determine its checksum) and run upkg_install
upkg_add() {
  local pkgtype=$1 pkgurl=$2 checksum=$3 pkgname=$4 no_exec=$5 no_bin=$6 force=$7 os_arch=$8; shift 8
  local binpaths=("$@")
  local prefetch prefetchpath

  if [[ -z "$checksum" ]]; then
    # Autocalculate the checksum
    processing "No checksum given for '%s', determining now" "$pkgurl"
    prefetch=true
  elif $force && [[ -z $pkgname ]]; then
    processing "No pkgname given for '%s', determining now" "$pkgurl"
    prefetch=true
  fi
  if $prefetch; then
    # Prefetch the package. Either because we need to determine the checksum
    # or because --force has been specified, and we need to remove a conflicting
    # package before installing (to that end we need to know the pkgname beforehand)
    # ... or because of both
    local prefetchpath
    if [[ $pkgtype != git ]]; then
      if [[ -e $pkgurl ]]; then
        # file exists locally on the filesystem
        prefetchpath=$pkgurl
        [[ -n $checksum ]] || checksum=$(sha256 "$pkgurl") # Don't override checksum if it was already given
      else
        mkdir .upkg/.tmp/prefetched
        prefetchpath=.upkg/.tmp/prefetched/tmpfile
        upkg_fetch "$pkgurl" "$prefetchpath"
        [[ -n $checksum ]] || checksum=$(sha256 "$prefetchpath")
        mv "$prefetchpath" ".upkg/.tmp/prefetched/$checksum"
        prefetchpath=.upkg/.tmp/prefetched/$checksum
      fi
    else
      # pkgurl is a git archive
      mkdir .upkg/.tmp/prefetched
      prefetchpath=.upkg/.tmp/prefetched/tmprepo
      if [[ -n $checksum ]]; then
        upkg_clone "$pkgurl" "$prefetchpath" "$checksum"
      else
        upkg_clone "$pkgurl" "$prefetchpath"
        checksum=$(git -C "$prefetchpath" rev-parse HEAD)
      fi
      mv "$prefetchpath" ".upkg/.tmp/prefetched/$checksum"
      prefetchpath=.upkg/.tmp/prefetched/$checksum
    fi
  fi

  local dep={}
  dep=$(jq --arg pkgtype "$pkgtype" --arg pkgurl "$pkgurl" '.[$pkgtype]=$pkgurl' <<<"$dep")
  if [[ $pkgtype = git ]]; then dep=$(jq --arg sha1 "$checksum" '.sha1=$sha1' <<<"$dep")
  else dep=$(jq --arg sha256 "$checksum" '.sha256=$sha256' <<<"$dep"); fi
  [[ -z $pkgname ]] || dep=$(jq --arg pkgname "$pkgname" '.name=$pkgname' <<<"$dep")
  ! $no_exec || dep=$(jq '.exec=false' <<<"$dep")
  if $no_bin; then
    dep=$(jq '.bin=[]' <<<"$dep")
  else
    local binpath
    for binpath in "${binpaths[@]}"; do
      dep=$(jq --arg binpath "$binpath" '.bin+=[$binpath]' <<<"$dep")
    done
  fi
  if $os_arch; then
    dep=$(jq --arg upkg_os_arch "$UPKG_OS_ARCH" '.["os/arch"]=$upkg_os_arch' <<<"$dep")
  fi

  # Modify upkg.json, but only in the temp dir, so a failure doesn't change anything
  local upkgjson={}
  [[ ! -e upkg.json ]] || upkgjson=$(cat upkg.json)

  if $force; then
    if [[ -z $pkgname ]]; then
      # Get the upkg.json contents to determine the pkgname, if the package is an archive, we need to extract it first
      local dep_upkgjson
      case "$pkgtype" in
        tar) dep_upkgjson=$(tar -xOf "$prefetchpath" upkg.json ./upkg.json 2>/dev/null || dep_upkgjson='{}') ;;
        zip) dep_upkgjson=$(unzip -qqp "$prefetchpath" upkg.json 2>/dev/null || dep_upkgjson='{}') ;;
        upkg) dep_upkgjson=$(cat "$prefetchpath") ;;
        file) dep_upkgjson='{}' ;;
        git) dep_upkgjson=$(cat "$prefetchpath/upkg.json" 2>/dev/null) || dep_upkgjson='{}' ;;
      esac
      pkgname=$(get_pkgname "$dep" "$dep_upkgjson" true)
    fi
    # Check if there is an existing package with the pkgname we are about to install, if so remove it from upkg.json first
    dep_idx=$(get_dep_idx "$pkgname")
    [[ -z $dep_idx ]] || upkgjson=$(jq -r --argjson dep_idx "$dep_idx" 'del(.dependencies[$dep_idx])' <<<"$upkgjson")
  fi

  jq --argjson dep "$dep" '.dependencies+=[$dep]' <<<"$upkgjson" >.upkg/.tmp/root/upkg.json
  upkg_install
  cp .upkg/.tmp/root/upkg.json upkg.json
}
