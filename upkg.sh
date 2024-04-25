#!/usr/bin/env bash
# shellcheck disable=2059,2064
set -eo pipefail
shopt -s inherit_errexit

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
  local cmd=$1; shift
  case "$cmd" in
    add)
      if [[ $# -ge 2 && $1 = -g ]]; then upkg_add "$INSTALL_PREFIX/lib/upkg" "$2" "$3" # upkg add -g URL [CHECKSUM]
      elif [[ $# -eq 1 || $# -eq 2 ]]; then upkg_add "$PWD" "$1" "$2"                  # upkg add URL [CHECKSUM]
      else fatal "$DOC"; fi                                                            # E_USAGE
      [[ ! -t 2 ]] || { ${UPKG_SILENT:-false} || printf "\n";} ;; # Add a newline after the processing lines
    remove)
      if [[ $# -eq 2 && $1 = -g ]]; then upkg_remove "$INSTALL_PREFIX/lib/upkg" "$2" # upkg remove -g PKGNAME
      elif [[ $# -eq 1 ]]; then upkg_remove "$PWD" "$1"                              # upkg remove PKGNAME
      else fatal "$DOC"; fi                                                          # E_USAGE
      [[ ! -t 2 ]] || { ${UPKG_SILENT:-false} || printf "\n";} ;;
    list)
      if [[ $1 = -g ]]; then shift; upkg_list "$INSTALL_PREFIX/lib/upkg" "$@" # upkg list -g ...
      else upkg_list "$PWD" "$@"; fi ;;                                       # upkg list ...
    install)
      if [[ $# -eq 1 && $1 = -n ]]; then DRY_RUN=true; upkg_install "$PWD" # upkg install -n
      elif [[ $# -eq 0 ]]; then DRY_RUN=false; upkg_install "$PWD"         # upkg install
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
  upkg_mktemp
  if [[ -z "$checksum" ]]; then
    # Autocalculate the checksum
    processing "No checksum given for '%s', determining now" "$pkgurl"
    if [[ $pkgurl =~ (\.tar(\.[^.?#/]+)?)([?#]|$) ]]; then
      local pkgext=${BASH_REMATCH[1]}
      if [[ $pkgurl =~ ^(https?://|ftps?://) ]]; then
        mkdir "$TMPPATH/prefetched"
        local tmp_archive="$TMPPATH/prefetched/temp-archive"
        upkg_fetch "$pkgurl" "$tmp_archive"
        checksum=$(shasum -a 256 "$tmp_archive" | cut -d ' ' -f1)
        mv "$tmp_archive" "$TMPPATH/prefetched/${checksum}${pkgext}"
      else
        checksum=$(shasum -a 256 "$pkgurl" | cut -d ' ' -f1)
      fi
    else
      # Use the remote HEAD get a git sha. This is what you would get when clone it without specifying any ref
      if ! checksum=$(git ls-remote -q "${pkgurl%'#'*}" HEAD | grep $'\tHEAD$' | cut -f1); then
        fatal "Unable to determine remote HEAD for '%s', assumed git repo from URL" "$pkgurl"
      fi
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
  upkg_mktemp
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
    local dep_pkgpath dedup_pkgpath basename pkgname checksum version upkgjsonpath version
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
  [[ -e "$pkgpath/upkg.json" ]] || fatal "No upkg.json found in '%s'" "$pkgpath"
  upkg_mktemp
  ln -s "$pkgpath/upkg.json" "$TMPPATH/root/upkg.json" 2>/dev/null || true
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
      [[ -e "$INSTALL_PREFIX/bin/$cmd" ]] || \
        fatal "conflict: the command '%s' already exists in '%s' but does not point to '%s'" \
          "$cmd" "$INSTALL_PREFIX/bin" "$INSTALL_PREFIX/lib/upkg"
    done < <(comm -23 <(printf "%s\n" "$available_cmds") <(printf "%s\n" "$global_cmds")) # available - global = new links
    while read -r -d $'\n' cmd; do
      # Same loop again, this time we are sure none of the new links exist
      ! $DRY_RUN || fatal "'%s' was not symlinked" "$INSTALL_PREFIX/bin/$cmd"
      processing "Linking '%s'" "$cmd"
      ln -s "../lib/upkg/.upkg/.bin/$cmd" "$INSTALL_PREFIX/bin/$cmd"
    done < <(comm -23 <(printf "%s\n" "$available_cmds") <(printf "%s\n" "$global_cmds"))
    while read -r -d $'\n' cmd; do
      # Remove all old links
      ! $DRY_RUN || fatal "'%s' should not be symlinked" "$INSTALL_PREFIX/bin/$cmd"
      rm "$INSTALL_PREFIX/bin/$cmd"
    done < <(comm -12 <(printf "%s\n" "$available_cmds") <(printf "%s\n" "$global_cmds")) # global - available = old links
  fi
  if ! $DRY_RUN; then
    if [[ -e "$pkgpath/.upkg" ]]; then
      # .bin/ and all pkgname symlinks are fully rebuilt during install, so we just remove it and copy it over
      find "$pkgpath/.upkg" -mindepth 1 -maxdepth 1 -not -name '.packages' -delete
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
    processing 'Installed all dependencies'
  else
    # Fail if dependencies have been removed. Though only at the top-level, the rest should/must be the same
    local dep_pkgpath
    while read -r -d $'\n' dep_pkgpath; do
      fatal "'%s' should not be installed" "$(basename "$dep_pkgpath")"
    done < <(comm -23 \
      <(find "$pkgpath/.upkg" -mindepth 1 -maxdepth 1 -not -name '.*' -exec readlink \{\} \; | sort) \
      <(find "$TMPPATH/root/.upkg" -mindepth 1 -maxdepth 1 -not -name '.*' -exec readlink \{\} \; | sort) # current pkgs - installed pkgs = unreferenced pkgs
    )
    processing 'All dependencies are up-to-date'
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
  local dep_pkgurl dep_checksum
  while read -r -d $'\n' dep_pkgurl; do
    read -r -d $'\n' dep_checksum
    # Run through deps and install them
    upkg_install_pkg "$dep_pkgurl" "$dep_checksum" "$pkgpath"
  done <<<"$deps"
}

# Obtain (copy, download, clone, extract.. whatever) a package, symlink its commands and the install its dependencies
upkg_install_pkg() {
  local pkgurl=$1 checksum=$2 parentpath=$3 pkgname pkgpath is_dedup=false
  if [[ -e "$DEDUPPATH" ]] && pkgpath=$(compgen -G "$DEDUPPATH/*@$checksum"); then
    # Package already exists in the destination
    $DRY_RUN || processing "Skipping '%s'" "$pkgurl"
    # Determine pkgname so we can symlink it
    pkgname=${pkgpath#"$DEDUPPATH/"}
    pkgname=${pkgname%"@$checksum"}
    is_dedup=true
  else
    ! $DRY_RUN || fatal "'%s' is not installed" "$pkgurl"
    # Obtain package
    pkgname=$(upkg_download "$pkgurl" "$checksum")
    pkgpath="$parentpath/.upkg/.packages/$pkgname@$checksum"
  fi
  # Atomic linking, if this fails there is a duplicate
  if ! ln -s ".packages/$pkgname@$checksum" "$parentpath/.upkg/$pkgname"; then
    fatal "conflict: The package '%s' is depended upon multiple times" "$pkgname"
  fi

  local command cmdpath
  if [[ -e "$pkgpath/bin" ]]; then
    # package has a bin/ dir, symlink the executable files in that directory
    mkdir -p "$parentpath/.upkg/.bin"
    while read -r -d $'\n' command; do
      command=$(basename "$command")
      cmdpath="$parentpath/.upkg/.bin/$command"
      # Atomic linking, if this fails there is a duplicate
      if ! ln -s "../$pkgname/bin/$command" "$cmdpath" 2>/dev/null; then
        local otherpkg
        otherpkg=$(basename "$(dirname "$(dirname "$(readlink "$cmdpath")")")")
        fatal "conflict: '%s' and '%s' both have a command named '%s'" "$pkgname" "$otherpkg" "$command"
      fi
    done < <(find "$pkgpath/bin" -mindepth 1 -maxdepth 1 -type f -executable)
  fi

  # Recursively install deps of this package
  $is_dedup || upkg_install_deps "$pkgpath"
}

# Copy, download, clone a package, check the checksum, maybe set a version, maybe calculate a pkgname, return the pkgname
upkg_download() (
  local pkgurl=$1 checksum=$2 pkgname
  mkdir -p "$TMPPATH/download"
  local downloadpath=$TMPPATH/download/$checksum
  # Create a lock so we never download a package more than once, and so other processes can wait for the download to finish
  exec 9<>"$downloadpath.lock"
  local already_downloading=false
  if ! flock -nx 9; then # Try getting an exclusive lock, if we can we are either the first, or the very last where everybody else is done
    already_downloading=true # Didn't get it, somebody is already downloading
    flock -s 9 # Block by trying to get a shared lock
  fi
  if pkgname=$(compgen -G "$TMPPATH/root/.upkg/.packages/*@$checksum"); then
    # The package has already been deduped
    processing "Already downloaded '%s'" "$pkgurl"
    # Get the pkgname from the dedup dir, output it, and exit early
    pkgname=${pkgname##*'/'}
    pkgname=${pkgname%@*}
    printf "%s\n" "$pkgname"
    return 0
  elif $already_downloading; then
    # Download failure somewhere. Don't try anything, just fail
    return 1
  fi
  mkdir "$downloadpath"
  mkdir -p "$TMPPATH/root/.upkg/.packages"
  # Check if we are dealing with a tar archive based on the URL
  if [[ $pkgurl =~ (\.tar(\.[^.?#/]+)?)([?#]|$) ]]; then
    local pkgext=${BASH_REMATCH[1]}
    local archivepath=${downloadpath}${pkgext} prefetchpath=$TMPDIR/prefetched/${checksum}${pkgext}
    [[ $checksum =~ ^[a-z0-9]{64}$ ]] || fatal "Checksum for '%s' is not sha256 (64 hexchars), assumed tar archive from URL"
    if [[ -e "$prefetchpath" ]]; then
      # archive was already downloaded by upkg_add to generate a checksum, reuse it
      archivepath=$prefetchpath
    elif [[ $pkgurl =~ ^(https?://|ftps?://) ]]; then
      upkg_fetch "$pkgurl" "$archivepath"
    else
      # archive is not a URL, so it's a path
      archivepath=${pkgurl%'#'*}
    fi
    shasum -a 256 -c <(printf "%s  %s" "$checksum" "$archivepath") >/dev/null
    tar -xf "$archivepath" -C "$downloadpath"
  else
    # refs are not allowed, upkg.json functions as a proper lockfile. refs ruin that.
    [[ $checksum =~ ^[a-z0-9]{40}$ ]] || fatal "Checksum for '%s' is not sha1 (40 hexchars), assumed git repo from URL"
    processing 'Cloning %s' "$pkgurl"
    local out
    out=$(git clone -q "${pkgurl%'#'*}" "$downloadpath" 2>&1) || \
      fatal "Unable to clone '%s'. Error:\n%s" "$pkgurl" "$out"
    out=$(git -C "$downloadpath" checkout -q "$checksum" -- 2>&1) || \
      fatal "Unable to checkout '%s' from '%s'. Error:\n%s" "$checksum" "$pkgurl" "$out"
    if [[ -e "$downloadpath/upkg.json" ]]; then
      # Add a version property to upkg.json
      local version upkgjson
      version=$(git -C "$downloadpath" describe 2>/dev/null) || version=$checksum
      upkgjson=$(jq --arg version "$version" '.version = $version' <"$downloadpath/upkg.json" || \
        fatal "The package from '%s' does not contain a valid upkg.json" "$pkgurl" "$pkgname")
      printf "%s\n" "$upkgjson" >"$downloadpath/upkg.json"
    fi
  fi
  if [[ $pkgurl =~ \#name=([^#]+)(\#|$) ]]; then
    # Package name override specified
    pkgname=${BASH_REMATCH[1]}
  elif [[ -e "$downloadpath/upkg.json" ]]; then
    # upkg.json is supplied, require that there is a name property
    pkgname=$(jq -re '.name // empty' "$downloadpath/upkg.json") || \
      fatal "The package from '%s' does not specify a package name in its upkg.json. \
You can fix the package or override the name by appending #name=PKGNAME to the URL"
  else
    # No name override or upkg.json supplied, fail
      fatal "The package from '%s' does not have a upkg.json. \
You can fix the package or override the name by appending #name=PKGNAME to the URL"
  fi
  # "@" and "/" may not be used at all in a package name. They may not begin with a "." either
  [[ $pkgname =~ ^[^@/]+$ || $pkgname = .* ]] || \
    fatal "The package from '%s' specifies an invalid package name: '%s'" "$pkgname"
  # Move to dedup path
  mv "$downloadpath" "$TMPPATH/root/.upkg/.packages/$pkgname@$checksum"
  printf "%s\n" "$pkgname"
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

# Idempotently create a temporary directory
upkg_mktemp() {
  [[ -z $TMPPATH ]] || return 0
  TMPPATH=$(mktemp -d)
  mkdir "$TMPPATH/root" # Precreate root dir, we always need it
  trap "rm -rf \"$TMPPATH\"" EXIT
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

fatal() {
  local tpl=$1; shift
  printf -- "upkg: $tpl\n" "$@" >&2
  return 1
}

upkg "$@"
