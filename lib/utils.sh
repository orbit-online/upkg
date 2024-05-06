#!/usr/bin/env bash

# Replace invalid pkgname characters with underscore
clean_pkgname() {
  local pkgname=$1
  pkgname=${pkgname//$'\n'/_} # Replace newline with _
  pkgname=${pkgname//'/'/_} # Replace / with _
  pkgname=${pkgname#'.'/_} # Replace starting '.' with _
  printf "%s\n" "$pkgname"
}

get_tar_suffix() {
  local pkgurl=$1
  if [[ -e "$pkgurl" ]]; then
    [[ $pkgurl =~ (\.tar(\.[^.?#/]+)?)$ ]] || \
      fatal "Unable to determine filename extension for tar archive, path must end in .tar or .tar.*"
    printf "%s\n" "${BASH_REMATCH[1]}"
  else
    [[ $pkgurl =~ (\.tar(\.[^.?#/]+)?)([?#]|$) ]] || \
      fatal "Unable to determine filename extension for tar archive, URL must end in .tar or .tar.* (? and # suffixes are allowed)"
    printf "%s\n" "${BASH_REMATCH[1]}"
  fi
}

sha256() {
  local filepath=$1 sha256=$2
  if [[ -n $sha256 ]]; then
    shasum -a 256 -c <(printf "%s  %s" "$sha256" "$filepath") >/dev/null
  else
    shasum -a 256 "$filepath" | cut -d ' ' -f1
  fi
}

# Descend through dependencies and resolve the links to .upkg/.packages directories
upkg_list_referenced_pkgs() {
  local pkgpath=$1 dep_pkgpath
  for dep_pkgpath in $(upkg_resolve_links "$pkgpath/.upkg"); do
    printf "%s\n" "$dep_pkgpath"
    [[ ! -e "$pkgpath/.upkg/$dep_pkgpath/.upkg" ]] || \
      upkg_resolve_links "$pkgpath/.upkg/$dep_pkgpath/.upkg"
  done
}

# List all commands in .upkg/.bin
upkg_list_available_cmds() {
  local pkgpath=$1 cmdpath
  [[ -e "$pkgpath/.upkg/.bin" ]] || return 0
  for cmdpath in "$pkgpath/.upkg/.bin"/*; do
    printf "%s\n" "$(basename "$cmdpath")"
  done
}

# List all global commands that link to $install_prefix/lib/upkg/.upkg/.bin
upkg_list_global_referenced_cmds() {
  local install_prefix=$1 cmdpath
  [[ -e "$install_prefix/bin" ]] || return 0
  for cmdpath in $(upkg_resolve_links "$install_prefix/bin"); do
    [[ $cmdpath != ../lib/upkg/.upkg/.bin/* ]] || printf "%s\n" "$(basename "$cmdpath")"
  done
}

upkg_resolve_links() {
  local path=$1 link
  for link in "$path"/*; do
    readlink "$link"
  done
}

# Idempotently create a temporary directory
upkg_mktemp() {
  local keep_dotupkg=false
  mkdir .upkg 2>/dev/null || keep_dotupkg=true
  mkdir .upkg/.tmp || fatal "Unable to create .upkg/.tmp, another upkg instance is possibly already installing to '%s'" "$PWD" # Implicit lock
  mkdir .upkg/.tmp/root # Precreate root dir, we always need it
  # shellcheck disable=SC2064
  if ! ${UPKG_KEEP_TMP:-false}; then
    # Cleanup when done, make sure no subshell ever calls these traps (set -E is on)
    if $DRY_RUN && ! $keep_dotupkg; then
      trap "[[ \$BASHPID != $BASHPID ]] || rm -rf .upkg" EXIT
    else
      trap "[[ \$BASHPID != $BASHPID ]] || rm -rf .upkg/.tmp" EXIT
      $keep_dotupkg || trap "[[ \$BASHPID != $BASHPID ]] || rm -rf .upkg" ERR
    fi
  fi
}

# Guess the type of a package by looking at the URL and checksum, fall back to doing a HEAD/ls-remote request
upkg_guess_pkgtype() {
  local pkgurl=$1 checksum=$2 pkgtype
  # shellcheck disable=SC2209
  if [[ $checksum =~ ^[a-z0-9]{40}$ ]]; then
    pkgtype=git
    verbose "Guessing pkgtype is git, based on 40 hexchars in checksum"
  elif [[ $checksum =~ ^[a-z0-9]{64}$ ]]; then
    if [[ $pkgurl =~ (\.tar(\.[^.?#/]+)?)([?#]|$) ]]; then
      pkgtype=tar
      verbose "Guessing pkgtype is tar, based on the checksum being 64 hexchars and the URL ending in .tar or .tar.*"
    else
      verbose "Guessing pkgtype is file, based on the checksum being 64 hexchars and the URL not ending in .tar or .tar.*"
      pkgtype=file
    fi
  elif [[ -e $pkgurl ]]; then
    if [[ -f $pkgurl ]]; then
      if [[ $pkgurl =~ (\.tar(\.[^.?#/]+)?)$ ]]; then
        pkgtype=tar
        verbose "Guessing pkgtype is tar, based on the URL being a file that exists on the machine and it ending in .tar or .tar.*"
      else
        pkgtype=file
        verbose "Guessing pkgtype is tar, based on the URL being a file that exists on the machine and it not ending in .tar or .tar.*"
      fi
    elif [[ -d $pkgurl ]] && [[ -e $pkgurl/HEAD || -e $pkgurl/.git/HEAD ]]; then
      pkgtype=git
      verbose "Guessing pkgtype is git, based on the URL being a directory that exists on the machine and <PATH>/HEAD or <PATH>/.git/HEAD existing"
    else
      fatal "Unable to determine package type from path '%s', please provide -t PKGTYPE" "$pkgurl"
    fi
  elif [[ $pkgurl =~ (\.tar(\.[^.?#/]+)?)([?#]|$) ]]; then
    pkgtype=tar
    verbose "Guessing pkgtype is tar, based on the URL ending in .tar or .tar.*"
  elif git ls-remote -q "${pkgurl%%'#'*}" HEAD >/dev/null 2>&1; then
    pkgtype=git
    verbose "Guessing pkgtype is git, based on \`git ls-remote HEAD <URL>\` not returning an error"
  elif upkg_head "$pkgurl"; then
    pkgtype=file
    verbose "Guessing pkgtype is file, based on wget/curl succeeding in doing a HEAD request to <URL>"
  else
    fatal "Unable to determine package type from URL '%s'" "$pkgurl"
  fi
  printf "%s\n" "$pkgtype"
}
