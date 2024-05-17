#!/usr/bin/env bash

# Copy, download, clone a package, check the checksum, maybe set a version, maybe calculate a package name, return the package name
upkg_download() {
  local dep=$1

  local pkgtype pkgurl checksum
  pkgtype=$(dep_pkgtype "$dep")
  pkgurl=$(dep_pkgurl "$dep")
  checksum=$(dep_checksum "$dep")

  mkdir -p .upkg/.tmp/download
  local pkgpath=.upkg/.tmp/download/$checksum

  # Create a lock so we never download a package more than once, and so other processes can wait for the download to finish
  exec 9<>"$pkgpath.lock"
  local already_downloading=false
  if ! flock -nx 9; then # Try getting an exclusive lock, if we can we are either the first, or the very last where everybody else is done
    already_downloading=true # Didn't get it, somebody is already downloading
    flock -s 9 # Block by trying to get a shared lock
  fi

  local dedup_pkgname_suffix # avoid clashes between tar and file pkgtypes by suffixing them (and just do it for git repos as well)
  case "$pkgtype" in
    tar) dedup_pkgname_suffix=.tar ;;
    file)
      # Suffix the name with +x or -x so we don't end up clashing with a dedup'ed dependency where "exec" is different
      if dep_is_exec "$dep"; then dedup_pkgname_suffix=+x
      else dedup_pkgname_suffix=-x; fi
      ;;
    git) dedup_pkgname_suffix=.git
  esac

  local dedup_pkgname
  if [[ -e .upkg/.tmp/root/.upkg/.packages ]] && dedup_pkgname=$(compgen -G ".upkg/.tmp/root/.upkg/.packages/*$dedup_pkgname_suffix@$checksum"); then
    # The package has already been deduped
    processing "Already downloaded '%s'" "$pkgurl"
    # Get the dedup_pkgname from the dedup dir, output it, and exit early
    dedup_pkgname=$(basename "$dedup_pkgname")
    printf "%s\n" "$dedup_pkgname"
    return 0
  elif $already_downloading; then
    # Download failure. Don't try anything, just fail
    return 1
  elif ! mkdir "$pkgpath" 2>/dev/null; then
    # Download failure, but the lock has already been released. Don't try anything, just fail
    return 1
  fi

  # Generate a preliminary dedup_pkgname (will be modified based on the pkgtype)
  dedup_pkgname=${pkgurl%%'#'*} # Remove trailing anchor
  dedup_pkgname=${dedup_pkgname%%'?'*} # Remove query params
  dedup_pkgname=$(basename "$dedup_pkgname") # Remove path prefix

  case "$pkgtype" in
    tar)
    local archivepath
    # check if file was already downloaded by upkg_add to generate a checksum
    if [[ -e ".upkg/.tmp/prefetched/$checksum" ]]; then
      # archive was already downloaded by upkg_add to generate a checksum
      archivepath=".upkg/.tmp/prefetched/$checksum"
    elif [[ -e $pkgurl ]]; then
      # archive exists on the filesystem, extract from it directly
      archivepath=$pkgurl
    else
      # archive does not exist on the filesystem, download it next to the pkgpath
      archivepath=$pkgpath.archive
      upkg_fetch "$pkgurl" "$archivepath"
    fi
    # Remove the suffix so that it is just ".tar". This is only to avoid ".tar.gz.tar" and is not strictly necessary
    [[ ! $dedup_pkgname =~ (\.tar(\.[^.?#/]+)?)$ ]] || dedup_pkgname=${dedup_pkgname%"${BASH_REMATCH[1]}"}

    sha256 "$archivepath" "$checksum"
    tar -xf "$archivepath" -C "$pkgpath"
    ;;
    file)
    # change the original $pkgpath which is a directory and an implicit lock
    pkgpath=$pkgpath.file
    if [[ -e ".upkg/.tmp/prefetched/$checksum" ]]; then
      # file was already downloaded by upkg_add to generate a checksum
      pkgpath=".upkg/.tmp/prefetched/$checksum"
    elif [[ -e $pkgurl ]]; then
      # file exists on the filesystem, copy it so it can be moved later on
      cp "$pkgurl" "$pkgpath"
      chmod -x "$pkgpath" # make sure no executable bits are preserved
    else
      # file does not exist on the filesystem, download it
      upkg_fetch "$pkgurl" "$pkgpath"
    fi

    sha256 "$pkgpath" "$checksum"
    chmod "$dedup_pkgname_suffix" "$pkgpath"
    ;;
    git)
    local out
    out=$(git clone -q "${pkgurl%%'#'*}" "$pkgpath" 2>&1) || \
      fatal "Unable to clone '%s'. Error:\n%s" "$pkgurl" "$out"
    out=$(git -C "$pkgpath" checkout -q "$checksum" -- 2>&1) || \
      fatal "Unable to checkout '%s' from '%s'. Error:\n%s" "$checksum" "$pkgurl" "$out"
    # Remove a potential .git suffix, we add it later on
    dedup_pkgname=${dedup_pkgname%".git"}
    ;;
  esac

  [[ ! -e "$pkgpath/.upkg" ]] || fatal "The package '%s' contains a .upkg/ directory. Unable to install." "$pkgurl"

  local pkgname
  if [[ -e "$pkgpath/upkg.json" ]] && pkgname=$(jq -re '.name // empty' "$pkgpath/upkg.json"); then
    dedup_pkgname=$pkgname
  fi
  dedup_pkgname=$(clean_pkgname "$dedup_pkgname")
  dedup_pkgname=${dedup_pkgname}${dedup_pkgname_suffix}

  # Move to dedup path
  mkdir -p .upkg/.tmp/root/.upkg/.packages
  mv "$pkgpath" ".upkg/.tmp/root/.upkg/.packages/$dedup_pkgname@$checksum"
  printf "%s\n" "$dedup_pkgname@$checksum"
}

# Download a file using wget or curl
upkg_fetch() {
  local url=$1 dest=$2 out
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
  local url=$1
  verbose "Performing a HEAD request to %s" "$url"
  if type wget >/dev/null 2>&1; then
    wget --spider -T "${UPKG_TIMEOUT:-10}" -t "${UPKG_FETCH_RETRIES:-2}" -q "$url" &>/dev/null
  elif type curl >/dev/null 2>&1; then
    curl -I -fsL --connect-timeout "${UPKG_TIMEOUT:-10}" --retry "${UPKG_FETCH_RETRIES:-2}" "$url" &>/dev/null
  else
    fatal "Unable to download '%s', neither wget nor curl are available" "$url"
  fi
}
