#!/usr/bin/env bash

# Replace invalid pkgname characters with underscore
clean_pkgname() {
  local pkgname=$1
  pkgname=${pkgname//$'\n'/_} # Replace newline with _
  pkgname=${pkgname//'/'/_} # Replace / with _
  pkgname=${pkgname#'.'/_} # Replace starting '.' with _
  printf "%s\n" "$pkgname"
}

SHASUM="shasum -a 256"
type shasum &>/dev/null || SHASUM=sha256sum
sha256() {
  local filepath=$1 sha256=$2
  if [[ -n $sha256 ]]; then
    $SHASUM -c <(printf "%s  %s" "$sha256" "$filepath") >/dev/null
  else
    $SHASUM "$filepath" | cut -d ' ' -f1
  fi
}

# List all commands in .upkg/.bin
upkg_list_available_cmds() {
  local pkgpath=$1 cmdpath
  [[ -e $pkgpath/.upkg/.bin ]] || return 0
  for cmdpath in "$pkgpath/.upkg/.bin"/*; do
    printf "%s\n" "$(basename "$cmdpath")"
  done
}

# List all global commands that link to $install_prefix/lib/upkg/.upkg/.bin
upkg_list_global_referenced_cmds() {
  local install_prefix=$1 cmdpath
  [[ -e $install_prefix/bin ]] || return 0
  while read -r -d $'\n' cmdpath; do
    [[ $cmdpath != ../lib/upkg/.upkg/.bin/* ]] || printf "%s\n" "$(basename "$cmdpath")"
  done < <(upkg_resolve_links "$install_prefix/bin")
}

upkg_list_referenced_pkgs() {
  local pkgpath=$1 pkglink dedup_pkgname
  while read -r -d $'\n' pkglink; do
    dedup_pkgname=$(basename "$pkglink")
    printf ".upkg/.packages/%s\n" "$dedup_pkgname"
    upkg_list_referenced_pkgs ".upkg/.packages/$dedup_pkgname"
  done < <(upkg_resolve_links "$pkgpath/.upkg")
}

upkg_resolve_links() {
  local path=$1 link
  for link in "$path"/*; do
    [[ ! -L "$link" ]] || printf "%s\n" "$(readlink "$link")"
  done
}

# Idempotently create a temporary directory
# Since we do this at the start of all operations that modify .upkg/ this is also an
# implicit of whether .upkg/ is writeable.
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
    elif [[ $pkgurl =~ (\.zip)([?#]|$) ]]; then
      pkgtype=zip
      verbose "Guessing pkgtype is zip, based on the checksum being 64 hexchars and the URL ending in .zip"
    elif [[ $pkgurl =~ (\.upkg\.json)([?#]|$) ]]; then
      pkgtype=upkg
      verbose "Guessing pkgtype is upkg, based on the checksum being 64 hexchars and the URL ending in upkg.json"
    else
      verbose "Guessing pkgtype is file, based on the checksum being 64 hexchars and the URL not ending in .tar or .tar.*"
      pkgtype=file
    fi
  elif [[ -e $pkgurl ]]; then
    if [[ -f $pkgurl ]]; then
      if [[ $pkgurl =~ (\.tar(\.[^.?#/]+)?)$ ]]; then
        pkgtype=tar
        verbose "Guessing pkgtype is tar, based on the URL being a file that exists on the machine and it ending in .tar or .tar.*"
      elif [[ $pkgurl =~ (\.zip)$ ]]; then
        pkgtype=zip
        verbose "Guessing pkgtype is zip, based on the URL being a file that exists on the machine and it ending in .zip"
      elif [[ $pkgurl =~ (\.upkg\.json)([?#]|$) ]]; then
        pkgtype=upkg
        verbose "Guessing pkgtype is upkg, based on the URL being a file that exists on the machine and it ending in upkg.json"
      else
        pkgtype=file
        verbose "Guessing pkgtype is file, based on the URL being a file that exists on the machine and it not ending in .tar or .tar.*"
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
  elif [[ $pkgurl =~ (\.zip)([?#]|$) ]]; then
    pkgtype=zip
    verbose "Guessing pkgtype is zip, based on the URL ending in .zip"
  elif [[ $pkgurl =~ (\.upkg\.json)([?#]|$) ]]; then
    pkgtype=upkg
    verbose "Guessing pkgtype is upkg, based on the URL ending in upkg.json"
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
