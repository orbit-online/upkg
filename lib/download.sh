#!/usr/bin/env bash

# Copy, download, clone a package, check the checksum, maybe set a version, maybe calculate a package name, return the package name
upkg_download() {
  local dep=$1

  local pkgtype pkgurl checksum
  pkgtype=$(dep_pkgtype "$dep")
  pkgurl=$(dep_pkgurl "$dep")
  checksum=$(dep_checksum "$dep")

  mkdir -p .upkg/.tmp/download
  local downloadpath=.upkg/.tmp/download/$checksum

  # Create a lock so we never download a package more than once, and so other processes can wait for the download to finish
  exec 9<>"$downloadpath.lock"
  local already_downloading=false
  if ! flock -nx 9; then # Try getting an exclusive lock, if we can we are either the first, or the very last where everybody else is done
    already_downloading=true # Didn't get it, somebody is already downloading
    flock -s 9 # Block by trying to get a shared lock
  fi

  local dedup_pkgname
  if dedup_pkgname=$(compgen -G ".upkg/.tmp/root/.upkg/.packages/*@$checksum"); then
    # The package has already been deduped
    processing "Already downloaded '%s'" "$pkgurl"
    # Get the dedup_pkgname from the dedup dir, output it, and exit early
    dedup_pkgname=$(basename "$dedup_pkgname")
    dedup_pkgname=${dedup_pkgname%@*}
    printf "%s\n" "$dedup_pkgname"
    return 0
  elif $already_downloading; then
    # Download failure. Don't try anything, just fail
    return 1
  elif ! mkdir "$downloadpath" 2>/dev/null; then
    # Download failure, but the lock has already been released. Don't try anything, just fail
    return 1
  fi
  mkdir -p .upkg/.tmp/root/.upkg/.packages

  local prefetchpath
  if [[ $pkgtype = tar ]]; then
    local filepath
    if prefetchpath=$(compgen -G ".upkg/.tmp/prefetched/${checksum}*"); then
      # file was already downloaded by upkg_add to generate a checksum, reuse it
      filepath=$prefetchpath
    elif [[ -e $pkgurl ]]; then
      # file exists on the filesystem, extract from it directly
      filepath=$pkgurl
    else
      # file does not exist on the filesystem, download it
      filepath="${downloadpath}$(get_tar_suffix "$pkgurl")"
      upkg_fetch "$pkgurl" "$filepath"
    fi

    sha256 "$filepath" "$checksum"
    tar -xf "$filepath" -C "$downloadpath"

  elif [[ $pkgtype = file ]]; then
    local filepath
    if prefetchpath=$(compgen -G ".upkg/.tmp/prefetched/${checksum}*"); then
      # file was already downloaded by upkg_add to generate a checksum, reuse it
      filepath=$prefetchpath
      downloadpath=$filepath
    elif [[ -e $pkgurl ]]; then
      # file exists on the filesystem, copy it so it can be moved later on
      filepath=$downloadpath.file
      downloadpath=$filepath
      cp "$pkgurl" "$downloadpath"
    else
      # file does not exist on the filesystem, download it
      # but don't download to $filepath (which is a directory)
      filepath=$downloadpath.file
      downloadpath=$filepath
      upkg_fetch "$pkgurl" "$filepath"
    fi

    sha256 "$filepath" "$checksum"
    if dep_exec "$dep"; then
      chmod +x "$downloadpath"
    fi

  elif [[ $pkgtype = git ]]; then
    processing 'Cloning %s' "$pkgurl"
    local out
    out=$(git clone -q "${pkgurl%%'#'*}" "$downloadpath" 2>&1) || \
      fatal "Unable to clone '%s'. Error:\n%s" "$pkgurl" "$out"
    out=$(git -C "$downloadpath" checkout -q "$checksum" -- 2>&1) || \
      fatal "Unable to checkout '%s' from '%s'. Error:\n%s" "$checksum" "$pkgurl" "$out"

    if [[ -e "$downloadpath/upkg.json" ]]; then
      # Add a version property to upkg.json
      local version upkgjson
      version=$(git -C "$downloadpath" describe 2>/dev/null) || version=$checksum
      upkgjson=$(jq --arg version "$version" '.version = $version' <"$downloadpath/upkg.json") || \
        fatal "The package from '%s' does not contain a valid upkg.json" "$pkgurl"
      printf "%s\n" "$upkgjson" >"$downloadpath/upkg.json"
    fi

  else
    fatal "Fetching of '%s' not implemented" "$pkgtype"
  fi

  [[ ! -e "$downloadpath/.upkg" ]] || fatal "The package '%s' contains a .upkg/ directory. Unable to install." "$pkgurl"

  if [[ ! -e "$downloadpath/upkg.json" ]] || ! dedup_pkgname=$(jq -re '.name // empty' "$downloadpath/upkg.json"); then
    # Generate a dedup_pkgname
    dedup_pkgname=${pkgurl%%'#'*} # Remove trailing anchor
    dedup_pkgname=${dedup_pkgname%%'?'*} # Remove query params
    dedup_pkgname=$(basename "$dedup_pkgname") # Remove path prefix
  fi
  dedup_pkgname=$(clean_pkgname "$dedup_pkgname")

  # Move to dedup path
  mv "$downloadpath" ".upkg/.tmp/root/.upkg/.packages/$dedup_pkgname@$checksum"
  printf "%s\n" "$dedup_pkgname@$checksum"
}

# Download a file using wget or curl
upkg_fetch() {
  local url="$1" dest="$2" out
  processing "Downloading %s" "$url"
  if type wget >/dev/null 2>&1; then
    out=$(wget --server-response -T "${UPKG_TIMEOUT:-10}" -t "${UPKG_FETCH_RETRIES:-2}" -qO "$dest" "$url" 2>&1) || \
      fatal "Error while downloading '%s', server response:\n%s" "$url" "$out"
  elif type curl >/dev/null 2>&1; then
    curl -fsL --connect-timeout "${UPKG_TIMEOUT:-10}" --retry "${UPKG_FETCH_RETRIES:-2}" -o "$dest" "$url" || \
      fatal "Error while downloading '%s'" "$url"
  else
    fatal "Unable to download '%s', neither wget nor curl are available" "$url"
  fi
}

upkg_head() {
  local url="$1"
  verbose "Performing a HEAD request to %s" "$url"
  if type wget >/dev/null 2>&1; then
    wget --spider -T "${UPKG_TIMEOUT:-10}" -t "${UPKG_FETCH_RETRIES:-2}" -q "$url" &>/dev/null
  elif type curl >/dev/null 2>&1; then
    curl -I -fsL --connect-timeout "${UPKG_TIMEOUT:-10}" --retry "${UPKG_FETCH_RETRIES:-2}" "$url" &>/dev/null
  else
    fatal "Unable to download '%s', neither wget nor curl are available" "$url"
  fi
}
