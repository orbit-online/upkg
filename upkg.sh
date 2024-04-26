#!/usr/bin/env bash
# shellcheck disable=2059,2064
set -Eeo pipefail

upkg() {
  [[ ! $(bash --version | head -n1) =~ version\ [34]\.[0-3] ]] || fatal "upkg requires bash >= v4.4"
  # Make sure we have jq available, git and tar are optional and we let them fail once we get there
  type "jq" >/dev/null 2>&1 || fatal "command not found: 'jq'"
  export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -oBatchMode=yes"}
  DOC="μpkg - A minimalist package manager
Usage:
  upkg add [-g] URL [CHECKSUM]
  upkg remove [-g] PKGNAME
  upkg list [-g] [\`column\` options]
  upkg install [-n]

Options:
  -g  Act globally
  -n  Dry run, \$?=1 if install/upgrade is required"
  unset TMPPATH # upkg_mktemp doesn't create a temppath if TMPPATH is set, make sure we don't reuse something else
  if [[ -z $INSTALL_PREFIX ]]; then # Allow the user to override the path prefix when using the global (-g) switch
    # Otherwise switch based on the UID
    INSTALL_PREFIX=$HOME/.local
    [[ $EUID != 0 ]] || INSTALL_PREFIX=/usr/local
  fi
  DRY_RUN=false
  local cmd=$1; shift || fatal "$DOC"
  case "$cmd" in
    add)
      upkg_mktemp
      if [[ $# -ge 2 && $1 = -g ]]; then upkg_add "$INSTALL_PREFIX/lib/upkg" "$2" "$3" # upkg add -g URL [CHECKSUM]
      elif [[ $# -eq 1 || $# -eq 2 ]]; then upkg_add "$PWD" "$1" "$2"                  # upkg add URL [CHECKSUM]
      else fatal "$DOC"; fi                                                            # E_USAGE
      [[ ! -t 2 ]] || { ${UPKG_SILENT:-false} || printf "\n";} ;; # Add a newline after the processing lines
    remove)
      upkg_mktemp
      if [[ $# -eq 2 && $1 = -g ]]; then upkg_remove "$INSTALL_PREFIX/lib/upkg" "$2" # upkg remove -g PKGNAME
      elif [[ $# -eq 1 ]]; then upkg_remove "$PWD" "$1"                              # upkg remove PKGNAME
      else fatal "$DOC"; fi                                                          # E_USAGE
      [[ ! -t 2 ]] || { ${UPKG_SILENT:-false} || printf "\n";} ;;
    list)
      if [[ $1 = -g ]]; then shift; upkg_list "$INSTALL_PREFIX/lib/upkg" "$@" # upkg list -g ...
      else upkg_list "$PWD" "$@"; fi ;;                                       # upkg list ...
    install)
      upkg_mktemp
      [[ -e "$PWD/upkg.json" ]] || fatal "No upkg.json found in '%s'" "$PWD"
      ln -s "$PWD/upkg.json" "$TMPPATH/root/upkg.json"
      if [[ $# -eq 1 && $1 = -n ]]; then DRY_RUN=true; upkg_install "$PWD" # upkg install -n
      elif [[ $# -eq 0 ]]; then upkg_install "$PWD"         # upkg install
      else fatal "$DOC"; fi                                                # E_USAGE
      [[ ! -t 2 ]] || { ${UPKG_SILENT:-false} || printf "\n";} ;;
    -h|--help)
      printf "%s\n" "$DOC" >&2 ;;
    *) fatal "$DOC" ;;
  esac
}

# Add a package from upkg.json (optionally determine its checksum) and run upkg_install
upkg_add() {
  local pkgpath=$1 pkgurl=$2 checksum=$3
  local upkgjson={}
  [[ ! -e "$pkgpath/upkg.json" ]] || upkgjson=$(cat "$pkgpath/upkg.json")
  if jq -re --arg pkgurl "$pkgurl" '.dependencies[$pkgurl] // empty' <<<"$upkgjson" >/dev/null; then
    # Package updates and the likes are not supported
    fatal "The package has already been added, run \`upkg remove %s\` first if you want to update it" "$(basename "$pkgurl")"
  fi
  if [[ -z "$checksum" ]]; then
    # Autocalculate the checksum
    processing "No checksum given for '%s', determining now" "$pkgurl"
    # Check if the URL is a tar, if not, try getting the remote HEAD git commit sha. If that fails, assume it's a file of some sort
    if [[ $pkgurl =~ (\.tar(\.[^.?#/]+)?)([?#]|$)|(#bin(#|$)) ]] || ! checksum=$(git ls-remote -q "${pkgurl%%'#'*}" HEAD 2>/dev/null | grep $'\tHEAD$' | cut -f1); then
      # pkgurl is a file
      local archiveext=${BASH_REMATCH[1]}
      if [[ -n $archiveext ]]; then # pkgurl is a tar archive
        validate_pkgurl "$pkgurl" tar
      else
        validate_pkgurl "$pkgurl" file
      fi
      if [[ -e ${pkgurl%%'#'*} ]]; then
        # file exists locally on the filesystem
        checksum=$(shasum -a 256 "${pkgurl%%'#'*}" | cut -d ' ' -f1)
      else
        mkdir "$TMPPATH/prefetched"
        local tmpfile="$TMPPATH/prefetched/tmpfile"
        upkg_fetch "$pkgurl" "$tmpfile"
        checksum=$(shasum -a 256 "$tmpfile" | cut -d ' ' -f1)
        mv "$tmpfile" "$TMPPATH/prefetched/${checksum}${archiveext}"
      fi
    else
      # pkgurl is a git archive
      validate_pkgurl "$pkgurl" git
    fi
  fi
  upkgjson=$(jq --arg url "$pkgurl" --arg checksum "$checksum" '.dependencies[$url]=$checksum' <<<"$upkgjson")
  # Modify upkg.json, but only in the temp dir, so a failure doesn't change anything
  printf "%s\n" "$upkgjson" >"$TMPPATH/root/upkg.json"
  upkg_install "$pkgpath"
  printf "%s\n" "$upkgjson" >"$pkgpath/upkg.json"
  processing "Added '%s'" "$pkgurl"
}

# Remove a package from upkg.json and run upkg_install
upkg_remove() {
  local pkgpath=$1 pkgname=$2
  local pkgurl upkgjson
  pkgurl=$(upkg_get_pkg_url "$pkgpath" "$pkgname")
  upkgjson=$(jq -r --arg pkgurl "$pkgurl" 'del(.dependencies[$pkgurl])' "$pkgpath/upkg.json")
  # Modify upkg.json, but only in the temp dir, so a failure doesn't change anything
  printf "%s\n" "$upkgjson" >"$TMPPATH/root/upkg.json"
  upkg_install "$pkgpath"
  printf "%s\n" "$upkgjson" >"$pkgpath/upkg.json"
  processing "Removed '%s'" "$pkgname"
}

# List all top-level installed packages. Not based on upkg.json, but the actually installed packages
upkg_list() {
  local pkgpath=$1; shift
  (
    local dedup_pkgpath basename pkgname checksum version upkgjsonpath version
    while read -r -d $'\n' dedup_pkgpath; do
      basename=$(basename "$dedup_pkgpath")
      pkgname=${basename%@*}
      checksum=${basename#*@}
      version='no-version'
      upkgjsonpath=$pkgpath/.upkg/$dedup_pkgpath/upkg.json
      [[ ! -e "$upkgjsonpath" ]] || version=$(jq -r '.version // "no-version"' "$upkgjsonpath")
      printf "%s\t%s\t%s\n" "$pkgname" "$version" "$checksum"
    done < <(find "$pkgpath/.upkg" -mindepth 1 -maxdepth 1 -not -name '.*' -exec readlink \{\} \;) # Don't descend into .packages, we only want the top-level
  ) | (
    # Allow nice formatting if `column` (from bsdextrautils) is installed
    if type column >/dev/null 2>&1; then
      column -t -n "Packages" -N "Package name,Version,Checksum" "$@" # Forward any extra options
    else
      cat # Not installed, just output the tab/newline separated data
    fi
  )
}

# Install all packages referenced upkg.json, remove existing ones that aren't, then do the same for their binary symlinks
upkg_install() {
  local pkgpath=$1
  DEDUPPATH="$pkgpath/.upkg/.packages" # The path to the non-temporary package dedup directory
  upkg_install_deps "$TMPPATH/root"
  # All deps installed, check and then symlink binaries globally
  if [[ $pkgpath = "$INSTALL_PREFIX/lib/upkg" ]]; then
    # Check that any global bin/ symlinks would not conflict with existing ones
    local available_cmds global_cmds cmd
    available_cmds=$(upkg_list_available_cmds "$TMPPATH/root" | sort) # Full list of commands that should be linked
    global_cmds=$(upkg_list_global_referenced_cmds "$INSTALL_PREFIX" | sort) # Current list of commands that are linked
    while read -r -d $'\n' cmd; do
      # None of the new links should exist, if they do they don't point to upkg (otherwise they would be in the available list)
      [[ ! -e "$INSTALL_PREFIX/bin/$cmd" ]] || \
        fatal "conflict: the command '%s' already exists in '%s' but does not point to '%s'" \
          "$cmd" "$INSTALL_PREFIX/bin" "$INSTALL_PREFIX/lib/upkg"
    done < <(comm -23 <(printf "%s" "$available_cmds") <(printf "%s" "$global_cmds")) # available - global = new links
  fi
  if ! $DRY_RUN; then
    if [[ -e "$pkgpath/.upkg" ]]; then
      # .bin/ and all pkgname symlinks are fully rebuilt during install, so we just remove it and copy it over
      rm -rf "$pkgpath/.upkg/.bin"
      find "$pkgpath/.upkg" -mindepth 1 -maxdepth 1 -not -name '.packages' -delete
    else
      mkdir -p "$pkgpath/.upkg"
    fi
    if [[ -e "$TMPPATH/root/.upkg" ]]; then
      # Merge copy the tmp directory (basically just merging .upkg/.packages)
      cp -a "$TMPPATH/root/.upkg" "$pkgpath/"
      # Remove all unreferenced packages
      local dep_pkgpath
      while read -r -d $'\n' dep_pkgpath; do
        rm -rf "$pkgpath/.upkg/$dep_pkgpath"
      done < <(comm -23 <(upkg_list_all_pkgs "$pkgpath" | sort) <(upkg_list_referenced_pkgs "$pkgpath" | sort)) # all pkgs - referenced pkgs = unreferenced pkgs
    else
      # The install may have resulted in all deps being remove. Don't keep the .upkg/ dir around
      rm -rf "$pkgpath/.upkg"
    fi
  else
    # Fail if dependencies have been removed. Though only at the top-level, the rest should/must be the same
    local dep_pkgpath
    while read -r -d $'\n' dep_pkgpath; do
      fatal "'%s' should not be installed" "$(basename "$dep_pkgpath")"
    done < <(comm -23 \
      <(find "$pkgpath/.upkg" -mindepth 1 -maxdepth 1 -not -name '.*' -exec readlink \{\} \; | sort) \
      <(find "$TMPPATH/root/.upkg" -mindepth 1 -maxdepth 1 -not -name '.*' -exec readlink \{\} \; | sort) # current pkgs - installed pkgs = unreferenced pkgs
    )
  fi
  if [[ $pkgpath = "$INSTALL_PREFIX/lib/upkg" ]]; then
    while read -r -d $'\n' cmd; do
      # Same loop again, this time we are sure none of the new links exist
      ! $DRY_RUN || fatal "'%s' was not symlinked" "$INSTALL_PREFIX/bin/$cmd"
      processing "Linking '%s'" "$cmd"
      mkdir -p "$INSTALL_PREFIX/bin/"
      ln -s "../lib/upkg/.upkg/.bin/$cmd" "$INSTALL_PREFIX/bin/$cmd"
    done < <(comm -23 <(printf "%s" "$available_cmds") <(printf "%s" "$global_cmds"))
    while read -r -d $'\n' cmd; do
      # Remove all old links
      ! $DRY_RUN || fatal "'%s' should not be symlinked" "$INSTALL_PREFIX/bin/$cmd"
      rm "$INSTALL_PREFIX/bin/$cmd"
    done < <(comm -12 <(printf "%s" "$available_cmds") <(printf "%s" "$global_cmds")) # global - available = old links
  fi
  if $DRY_RUN; then
    processing 'All dependencies are up-to-date'
  else
    processing 'Installed all dependencies'
  fi
}

# Get the URL of a package via its package name
upkg_get_pkg_url() {
  local pkgpath=$1 pkgname=$2 checksum
  [[ -e "$pkgpath/.upkg/$pkgname" ]] || fatal "Unable to find '%s' in '%s'" "$pkgname" "$pkgpath/.upkg"
  # Use the .upkg/pkg symlink to get the .package path ...
  checksum=$(readlink "$pkgpath/.upkg/$pkgname")
  checksum=$(basename "$checksum")
  # ... extract the checksum from that name ...
  checksum=${checksum#*@}
  # ... and then look it up in upkg.json
  if ! jq -re --arg checksum "$checksum" '.dependencies | to_entries[] | select(.value==$checksum) | .key // empty' "$pkgpath/upkg.json"; then
    fatal "'%s' is not listed in '%s'" "$pkgname" "$pkgpath/upkg.json"
  fi
}

# List all directories in .upkg/.packages
upkg_list_all_pkgs() {
  local pkgpath=$1
  (cd "$pkgpath/.upkg"; find .packages -mindepth 1 -maxdepth 1)
}

# Descend through dependencies and resolve the links to .upkg/.packages directories
upkg_list_referenced_pkgs() {
  local pkgpath=$1 dep_pkgpath
  while read -r -d $'\n' dep_pkgpath; do
    printf "%s\n" "$dep_pkgpath"
    [[ ! -e "$pkgpath/.upkg/$dep_pkgpath/.upkg" ]] || \
      find "$pkgpath/.upkg/$dep_pkgpath/.upkg" -mindepth 1 -maxdepth 1 -not -name '.*' -exec readlink \{\} \;
  done < <(find "$pkgpath/.upkg" -mindepth 1 -maxdepth 1 -not -name '.*' -exec readlink \{\} \;)
}

# List all commands in .upkg/.bin
upkg_list_available_cmds() {
  local pkgroot=$1 cmdpath
  [[ -e "$pkgroot/.upkg/.bin" ]] || return 0
  while read -r -d $'\n' cmdpath; do
    printf "%s\n" "${cmdpath#"$pkgroot/.upkg/.bin/"}"
  done < <(find "$pkgroot/.upkg/.bin" -mindepth 1 -maxdepth 1)
}

# List all global commands that link to $install_prefix/lib/upkg/.upkg/.bin
upkg_list_global_referenced_cmds() {
  local install_prefix=$1 cmdpath
  [[ -e "$install_prefix/bin" ]] || return 0
  while read -r -d $'\n' cmdpath; do
    [[ $cmdpath != ../lib/upkg/.upkg/.bin/* ]] || printf "%s\n" "${cmdpath#'../lib/upkg/.upkg/.bin/'}"
  done < <(find "$install_prefix/bin" -mindepth 1 -maxdepth 1 -exec readlink \{\} \;)
}

# Install all dependencies of a package
upkg_install_deps() {
  local pkgpath=$1 deps
  # Loads of early returns here
  [[ -e "$pkgpath/upkg.json" ]] || return 0 # No upkg.json -> no deps -> nothing to do
  deps=$(jq -r '(.dependencies // []) | to_entries[] | .key, .value' "$pkgpath/upkg.json")
  [[ -n $deps ]] || return 0 # No deps -> nothing to do
  mkdir "$pkgpath/.upkg" 2>/dev/null || return 0 # .upkg exists -> another process is already installing the deps
  if [[ $pkgpath = "$TMPPATH/root" ]]; then
    mkdir "$pkgpath/.upkg/.packages" # We are at the root, this should be a directory, and not just a link
  else
    ln -s ../../ "$pkgpath/.upkg/.packages" # Deeper dependency, link to the parent dedup directory
  fi
  # Create sentinels dir where subprocesses create a file which indicates that
  # the shared lock on upkg.json has been acquired.
  # If the install fails they will create a file indicating the failure
  mkdir "$pkgpath/.upkg/.sentinels"
  local dep_pkgurl dep_checksum
  while read -r -d $'\n' dep_pkgurl; do
    read -r -d $'\n' dep_checksum
    # Run through deps and install them concurrently
    if ${UPKG_SEQUENTIAL:-false}; then
      # Debug flag for sequential install has been set.
      # Don't background anything, but still ignore the exit code and rely on the sentinels.
      # And yes, this is how you do it. "|| true" disables errexit for the entire subshell.
      set +e; (set -e; upkg_install_pkg "$dep_pkgurl" "$dep_checksum" "$pkgpath"); set -e
    else
      upkg_install_pkg "$dep_pkgurl" "$dep_checksum" "$pkgpath" &
    fi
  done <<<"$deps"
  while read -r -d $'\n' dep_pkgurl; do
    read -r -d $'\n' dep_checksum
    # Wait for each lock sentinel to exist
    until [[ -e "$pkgpath/.upkg/.sentinels/$dep_checksum.lock" ]]; do sleep .01; done
  done <<<"$deps"
  # All install processes have acquired the shared lock, we can now wait for all shared locks to be released
  exec 8<>"$pkgpath/upkg.json"; flock -x 8
  while read -r -d $'\n' dep_pkgurl; do
    read -r -d $'\n' dep_checksum
    # Check that no processes failed
    [[ ! -e "$pkgpath/.upkg/.sentinels/$dep_checksum.fail" ]] || \
      fatal "An error occurred while installing '%s'" "$dep_pkgurl"
  done <<<"$deps"
  rm -rf "$pkgpath/.upkg/.sentinels" # Done, remove the lock sentinels
}

# Obtain (copy, download, clone, extract.. whatever) a package, symlink its commands and the install its dependencies
upkg_install_pkg() {
  local pkgurl=$1 checksum=$2 parentpath=$3 dedupname pkgname is_dedup=false
  # Acquire a shared lock which is released once this process completes. Fail if we can't lock
  exec 9<>"$parentpath/upkg.json"; flock -ns 9
  touch "$parentpath/.upkg/.sentinels/$checksum.lock" # Tell the parent process that the shared lock has been acquired
  trap "touch \"$parentpath/.upkg/.sentinels/$checksum.fail\"" ERR # Inform parent process when an error occurs
  if [[ -e "$DEDUPPATH" ]] && dedupname=$(compgen -G "$DEDUPPATH/*@$checksum"); then
    # Package already exists in the destination, all we need is the deduppath so we can symlink it
    $DRY_RUN || processing "Skipping '%s'" "$pkgurl"
    dedupname=${dedupname#"$DEDUPPATH/"}
    dedupname=${dedupname%@*}
    is_dedup=true
  else
    ! $DRY_RUN || fatal "'%s' is not installed" "$pkgurl"
    # Obtain package
    dedupname=$(upkg_download "$pkgurl" "$checksum")
  fi
  pkgname=$dedupname
  if [[ $pkgurl =~ \#name=([^#]+)(\#|$) ]]; then
    # Package name override specified
    pkgname=${BASH_REMATCH[1]}
  fi
  [[ $pkgname =~ ^[@/]+$ || $pkgname != .* ]] ||
    fatal "The package from '%s' has an invalid package name or name override \
('@/' are disallowed, may not be empty or start with '.'): '%s'" "$pkgurl" "$pkgname"

  # Atomic linking, if this fails there is a duplicate
  if ! ln -s ".packages/$dedupname@$checksum" "$parentpath/.upkg/$pkgname"; then
    # TODO: Generate dependency tree from pkgpath
    fatal "conflict: There is more than one package with the name '%s'" "$pkgname"
  fi

  local pkgpath="$parentpath/.upkg/$dedupname" command cmdpath otherpkg
  if [[ -e "$pkgpath/bin" ]]; then
    # package has a bin/ dir, symlink the executable files in that directory
    mkdir -p "$parentpath/.upkg/.bin"
    while read -r -d $'\n' command; do
      command=$(basename "$command")
      cmdpath="$parentpath/.upkg/.bin/$command"
      # Atomic linking, if this fails there is a duplicate
      if ! ln -s "../$pkgname/bin/$command" "$cmdpath" 2>/dev/null; then
        otherpkg=$(readlink "$cmdpath")
        otherpkg=${otherpkg#'../'}
        otherpkg=${otherpkg%%'/'*}
        fatal "conflict: '%s' and '%s' both have a command named '%s'" "$pkgname" "$otherpkg" "$command"
      fi
    done < <(find "$pkgpath/bin" -mindepth 1 -maxdepth 1 -type f -executable)
  elif [[ $pkgurl =~ \#bin(\#|$) ]]; then
    # pkgurl is a file (and has been validated as such in upkg_download), symlink from bin
    mkdir -p "$parentpath/.upkg/.bin"
    command=$(basename "${pkgurl%%'#'*}")
    cmdpath="$parentpath/.upkg/.bin/$command"
    # Atomic linking, if this fails there is a duplicate
    if ! ln -s "../$pkgname" "$cmdpath" 2>/dev/null; then
      otherpkg=$(readlink "$cmdpath")
      otherpkg=${otherpkg#'../'}
      otherpkg=${otherpkg%%'/'*}
      fatal "conflict: '%s' and '%s' both have a command named '%s'" "$pkgname" "$otherpkg" "$command"
    fi
  fi

  # Recursively install deps of this package unless it is already dedup'ed
  $is_dedup || upkg_install_deps "$pkgpath"
}

# Copy, download, clone a package, check the checksum, maybe set a version, maybe calculate a pkgname, return the pkgname
upkg_download() (
  local pkgurl=$1 checksum=$2 dedupname
  mkdir -p "$TMPPATH/download"
  local pkgpath=$TMPPATH/download/$checksum
  # Create a lock so we never download a package more than once, and so other processes can wait for the download to finish
  exec 9<>"$pkgpath.lock"
  local already_downloading=false
  if ! flock -nx 9; then # Try getting an exclusive lock, if we can we are either the first, or the very last where everybody else is done
    already_downloading=true # Didn't get it, somebody is already downloading
    flock -s 9 # Block by trying to get a shared lock
  fi
  if dedupname=$(compgen -G "$TMPPATH/root/.upkg/.packages/*@$checksum"); then
    # The package has already been deduped
    processing "Already downloaded '%s'" "$pkgurl"
    # Get the dedupname from the dedup dir, output it, and exit early
    dedupname=${dedupname#"$TMPPATH/root/.upkg/.packages/"}
    dedupname=${dedupname%@*}
    printf "%s\n" "$dedupname"
    return 0
  elif $already_downloading; then
    # Download failure. Don't try anything, just fail
    return 1
  elif ! mkdir "$pkgpath" 2>/dev/null; then
    # Download failure, but the lock has already been released. Don't try anything, just fail
    return 1
  fi
  mkdir -p "$TMPPATH/root/.upkg/.packages"
  # Check if the URL is a tar, if not, try getting the remote HEAD commit sha. If that fails, assume it's a file of some sort
  if [[ $pkgurl =~ (\.tar(\.[^.?#/]+)?)([?#]|$)|(#bin(#|$)) ]] || ! git ls-remote -q "${pkgurl%%'#'*}" HEAD >/dev/null 2>&1; then
    local archiveext=${BASH_REMATCH[1]} # Empty if we are not dealing with an archive
    local prefetchpath=$TMPPATH/prefetched/${checksum}${archiveext} filepath=${pkgpath}${archiveext}
    if [[ -n $archiveext ]]; then
      validate_pkgurl "$pkgurl" tar
    else
      validate_pkgurl "$pkgurl" file
    fi
    [[ $checksum =~ ^[a-z0-9]{64}$ ]] || \
      fatal "Checksum for '%s' is not sha256 (64 hexchars), assumed tar archive from URL" "$pkgurl"
    if [[ -e "$prefetchpath" ]]; then
      # file was already downloaded by upkg_add to generate a checksum, reuse it
      filepath=$prefetchpath
      [[ -n $archiveext ]] || pkgpath=$filepath
    elif [[ -e ${pkgurl%%'#'*} ]]; then
      # file exists on the filesystem
      if [[ -n $archiveext ]]; then
        filepath=${pkgurl%%'#'*}
      else
        # File is not an archive, copy it so it can be moved later on
        filepath=$pkgpath.file
        pkgpath=$filepath
        cp "${pkgurl%%'#'*}" "$pkgpath"
      fi
    else
      if [[ -z $archiveext ]]; then
        # File is not an archive, don't download to $filepath (which is a directory)
        filepath=$pkgpath.file
        pkgpath=$filepath
      fi
      upkg_fetch "$pkgurl" "$filepath"
    fi
    shasum -a 256 -c <(printf "%s  %s" "$checksum" "$filepath") >/dev/null
    if [[ -n $archiveext ]]; then # file is an archive, extract
      tar -xf "$filepath" -C "$pkgpath"
    elif [[ $pkgurl =~ \#bin(\#|$) ]]; then # file has been marked as an executable, chmod
      chmod +x "$pkgpath"
    fi
  else
    # refs are not allowed, upkg.json functions as a proper lockfile. refs ruin that.
    [[ $checksum =~ ^[a-z0-9]{40}$ ]] || \
      fatal "Checksum for '%s' is not sha1 (40 hexchars), assumed git repo from URL" "$pkgurl"
    validate_pkgurl "$pkgurl" git
    processing 'Cloning %s' "$pkgurl"
    local out
    out=$(git clone -q "${pkgurl%%'#'*}" "$pkgpath" 2>&1) || \
      fatal "Unable to clone '%s'. Error:\n%s" "$pkgurl" "$out"
    out=$(git -C "$pkgpath" checkout -q "$checksum" -- 2>&1) || \
      fatal "Unable to checkout '%s' from '%s'. Error:\n%s" "$checksum" "$pkgurl" "$out"
    if [[ -e "$pkgpath/upkg.json" ]]; then
      # Add a version property to upkg.json
      local version upkgjson
      version=$(git -C "$pkgpath" describe 2>/dev/null) || version=$checksum
      upkgjson=$(jq --arg version "$version" '.version = $version' <"$pkgpath/upkg.json") || \
        fatal "The package from '%s' does not contain a valid upkg.json" "$pkgurl"
      printf "%s\n" "$upkgjson" >"$pkgpath/upkg.json"
    fi
  fi
  # Generate a dedupname
  dedupname=${pkgurl%%'#'*} # Remove trailing anchor
  dedupname=${dedupname%%'?'*} # Remove query params
  dedupname=$(basename "$dedupname") # Remove path prefix
  dedupname=${dedupname//@/_} # Replace @ with _
  dedupname=${dedupname#'.'/_} # Starting '.' with _
  local upkgname
  if [[ -e "$pkgpath/upkg.json" ]] && upkgname=$(jq -re '.name // empty' "$pkgpath/upkg.json"); then
    # upkg.json is supplied, validate the name property or keep the generated one
    if [[ $upkgname =~ ^[@/]+$ || $upkgname != .* ]]; then
      dedupname=$upkgname
    else
      warning "The package from '%s' specifies an invalid package name (contains @ or /, is empty or starts with '.'): '%s'" "$pkgurl" "$upkgname"
    fi
  fi
  # Move to dedup path
  mv "$pkgpath" "$TMPPATH/root/.upkg/.packages/$dedupname@$checksum"
  printf "%s\n" "$dedupname"
)

# Download a file using wget or curl
upkg_fetch() {
  local url="$1" dest="$2" out
  processing "Downloading %s" "$url"
  if type wget >/dev/null 2>&1; then
    wget -qO "$dest" "$url" || fatal "Error while downloading '%s'" "$url"
  elif type curl >/dev/null 2>&1; then
    curl -fsLo "$dest" "$url" || fatal "Error while downloading '%s'" "$url"
  else
    fatal "Unable to download '%s', neither wget nor curl are available" "$url"
  fi
}

validate_pkgurl() {
  local pkgurl=$1 urltype=$2
  [[ $urltype != tar || ! $pkgurl =~ \#bin(\#|$) ]] || \
    fatal "'%s' has been marked with #bin to be an executable, but the URL points at a tar archive" "$pkgurl"
  [[ $urltype != git || ! $pkgurl =~ \#bin(\#|$) ]] || \
    fatal "'%s' has been marked with #bin to be an executable, but the URL points at a git repository" "$pkgurl"
  [[ $pkgurl =~ (\#name=([^.][^#@/]+)(\#|$))? ]] || \
    fatal "The package URL '%s' specifies an invalid package name override (contains @ or /, is empty or starts with '.')'" "$pkgurl"
}

# Idempotently create a temporary directory
upkg_mktemp() {
  TMPPATH=$(mktemp -d)
  mkdir "$TMPPATH/root" # Precreate root dir, we always need it
  if ${UPKG_KEEP_TMPPATH:-false}; then
    # Debug flag for leaving the TMPPATH has been set, don't remove when done
    trap "printf \"TMPPATH=%s\n\" \"$TMPPATH\"" EXIT
  else
    # Cleanup when done
    trap "rm -rf \"$TMPPATH\"" EXIT
  fi
}

processing() {
  ! ${UPKG_SILENT:-false} || return 0
  local tpl=$1; shift
  if [[ -t 2 ]]; then
    printf -- "\e[2Kupkg: $tpl\r" "$@" >&2
  else
    printf -- "upkg: $tpl\n" "$@" >&2
  fi
}

warning() {
  ! ${UPKG_SILENT:-false} || return 0
  local tpl=$1; shift
  if [[ -t 2 ]]; then
    printf -- "\e[2Kupkg: $tpl\n" "$@" >&2
  else
    printf -- "upkg: $tpl\n" "$@" >&2
  fi
}

fatal() {
  local tpl=$1; shift
  if [[ -t 2 ]]; then
    printf -- "\e[2Kupkg: $tpl\n" "$@" >&2
  else
    printf -- "upkg: $tpl\n" "$@" >&2
  fi
  return 1
}

upkg "$@"
