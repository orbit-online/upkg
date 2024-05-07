#!/usr/bin/env bash
# shellcheck source-path=..
set -Eeo pipefail; shopt -s inherit_errexit nullglob

# Install all packages referenced upkg.json, remove existing ones that aren't, then do the same for their command symlinks
upkg_install() {
  upkg_install_deps .upkg/.tmp/root
  local is_global=false
  if [[ $PWD = "$INSTALL_PREFIX/lib/upkg" ]]; then
    is_global=true
    local \
      available_cmds \
      global_cmds \
      new_links=() \
      removed_links=() \
      cmd
  fi

  # All deps installed, pre-flight check command symlinks
  if $is_global; then
    # Check that any global bin/ symlinks would not conflict with existing ones
    available_cmds=$(upkg_list_available_cmds .upkg/.tmp/root | sort) # Full list of commands that should be linked
    global_cmds=$(upkg_list_global_referenced_cmds "$INSTALL_PREFIX" | sort) # Current list of commands that are linked
    readarray -t -d $'\n' new_links < <(comm -23 <(printf "%s\n" "$available_cmds") <(printf "%s\n" "$global_cmds"))
    for cmd in "${new_links[@]}"; do
      [[ -n $cmd ]] || continue # comm returns an empty string when comparing "\n" and "whatever\n" (for example when removing the last package with commands)
      # None of the new links should exist, if they do they don't point to upkg (otherwise they would be in the available list)
      [[ ! -e "$INSTALL_PREFIX/bin/$cmd" ]] || \
        fatal "conflict: the command '%s' already exists in '%s' but does not point to '%s'" \
          "$cmd" "$INSTALL_PREFIX/bin" "$INSTALL_PREFIX/lib/upkg"
    done
  fi

  # Copy new packages and all symlinks from .upkg/.tmp
  if ! $DRY_RUN; then
    # .bin/ and all pkgname symlinks are fully rebuilt during install, so we just remove it and copy it over
    rm -rf .upkg/.bin
    rm -f .upkg/* # "*" works here because we don't have nullglob on and dotglob off, meaning don't match .packages/ and .tmp/
    if [[ -e .upkg/.tmp/root/.upkg ]]; then
      if [[ -e .upkg/.tmp/root/.upkg/.packages ]]; then
        mkdir -p .upkg/.packages
        mv -nt .upkg/.packages .upkg/.tmp/root/.upkg/.packages/*
      fi
      [[ ! -e .upkg/.tmp/root/.upkg/.bin ]] || mv -nt .upkg/ .upkg/.tmp/root/.upkg/.bin
      mv -nt .upkg .upkg/.tmp/root/.upkg/*
      # Remove all unreferenced packages
      local dep_pkgpath unreferenced_pkgs=()
      readarray -t -d $'\n' unreferenced_pkgs < <(comm -23 <(cd .upkg; for dedup_path in .packages/*; do echo "$dedup_path"; done | sort) <(upkg_list_referenced_pkgs . | sort))
      for dep_pkgpath in "${unreferenced_pkgs[@]}"; do
        rm -rf ".upkg/$dep_pkgpath"
      done
    else
      # The install resulted in all deps being removed. Don't keep the .upkg/ dir around
      rm -rf .upkg
    fi
  else
    # Fail if dependencies have been removed.
    local dep_pkgpath unreferenced_pkgs=()
    # current pkgs - installed pkgs = unreferenced pkgs
    readarray -t -d $'\n' unreferenced_pkgs < <(comm -23 <(upkg_resolve_links .upkg | sort) <(upkg_resolve_links .upkg/.tmp/root/.upkg | sort))
    for dep_pkgpath in "${unreferenced_pkgs[@]}"; do
      fatal "'%s' should not be installed" "$(basename "$dep_pkgpath")"
    done
  fi

  # All packages copied successfully, symlink commands
  if $is_global; then
    # Recalculate the available commands after install
    available_cmds=$(upkg_list_available_cmds . | sort) # Full list of commands that should be linked
    # global - available = new links
    local new_links=()
    readarray -t -d $'\n' new_links < <(comm -23 <(printf "%s\n" "$available_cmds") <(printf "%s\n" "$global_cmds"))
    for cmd in "${new_links[@]}"; do
      [[ -n $cmd ]] || continue # See above
      # Same loop again, this time we are sure none of the new links exist
      ! $DRY_RUN || fatal "'%s' was not symlinked" "$INSTALL_PREFIX/bin/$cmd"
      processing "Linking '%s'" "$cmd"
      mkdir -p "$INSTALL_PREFIX/bin"
      ln -sT "../lib/upkg/.upkg/.bin/$cmd" "$INSTALL_PREFIX/bin/$cmd"
    done
    # available - global = old links
    local removed_links=()
    readarray -t -d $'\n' removed_links < <(comm -13 <(printf "%s\n" "$available_cmds") <(printf "%s\n" "$global_cmds"))
    for cmd in "${removed_links[@]}"; do
      [[ -n $cmd ]] || continue # See above
      # Remove all old links
      ! $DRY_RUN || fatal "'%s' should not be symlinked" "$INSTALL_PREFIX/bin/$cmd"
      rm "$INSTALL_PREFIX/bin/$cmd"
    done
  fi
}

# Install all dependencies of a package
upkg_install_deps() {
  local pkgpath=$1 deps=()

  # Loads of early returns here
  [[ -e "$pkgpath/upkg.json" ]] || return 0 # No upkg.json -> no deps -> nothing to do
  readarray -t -d $'\n' deps < <(jq -rc '(.dependencies // [])[]' "$pkgpath/upkg.json")
  [[ ${#deps[@]} -gt 0 ]] || return 0 # No deps -> nothing to do
  mkdir "$pkgpath/.upkg" 2>/dev/null || return 0 # .upkg exists -> another process is already installing the deps
  # Let upkg_download create the real dedup directory, indicating something was actually fetched
  if [[ $pkgpath != .upkg/.tmp/root ]]; then
    ln -sT ../../ "$pkgpath/.upkg/.packages" # Dependency, link to the parent dedup directory
  fi

  # Create sentinels dir where subprocesses create a file which indicates that
  # the shared lock on upkg.json has been acquired.
  # If the install fails they will create a file indicating the failure
  mkdir "$pkgpath/.upkg/.sentinels"

  local dep dep_idx=0
  # Run through deps and install them concurrently
  for dep in "${deps[@]}"; do
    upkg_install_dep "$pkgpath" "$dep" "$dep_idx" &
    if ${UPKG_SEQUENTIAL:-false}; then
      # Wait for upkg_install_dep to take the exclusive lock before spawning the next subshell.
      # This way we ensure a deterministic install order
      until [[ -e "$pkgpath/.upkg/.sentinels/$dep_idx.lock" || -e "$pkgpath/.upkg/.sentinels/$dep_idx.fail" ]]; do sleep .01; done
    fi
    # checksums are not unique across dependencies, so we use the dependencies array order as a key instead
    : $((dep_idx++))
  done

  dep_idx=0
  for dep in "${deps[@]}"; do
    # Wait for each lock sentinel to exist
    until [[ -e "$pkgpath/.upkg/.sentinels/$dep_idx.lock" || -e "$pkgpath/.upkg/.sentinels/$dep_idx.fail" ]]; do sleep .01; done
    : $((dep_idx++))
  done

  # All install processes have acquired the shared lock, we can now wait for all shared locks to be released
  exec 8<>"$pkgpath/upkg.json"; flock -x 8

  # All processes have either succeeded or failed, check the result
  dep_idx=0
  for dep in "${deps[@]}"; do
    # Check that no processes failed
    [[ ! -e "$pkgpath/.upkg/.sentinels/$dep_idx.fail" ]] || \
      fatal "An error occurred while installing '%s'" "$(dep_pkgurl "$dep")"
    : $((dep_idx++))
  done
  rm -rf "$pkgpath/.upkg/.sentinels" # Done, remove the lock sentinels
}

# Obtain (copy, download, clone, extract.. whatever) a package, symlink its commands and the install its dependencies
upkg_install_dep() {
  local parent_pkgpath=$1 dep=$2 dep_idx=$3

  trap "" EXIT # Clear parent process trap
  # shellcheck disable=SC2064
  trap "touch \"$parent_pkgpath/.upkg/.sentinels/$dep_idx.fail\"" ERR # Inform parent process when an error occurs
  exec 9<>"$parent_pkgpath/upkg.json"
  if ${UPKG_SEQUENTIAL:-false}; then flock -x 9 # Acquire an exclusive lock which is released once this process completes. Fail if we can't lock
  else flock -ns 9; fi # Acquire a shared lock which is released once this process completes. Fail if we can't lock
  touch "$parent_pkgpath/.upkg/.sentinels/$dep_idx.lock" # Tell the parent process that the shared lock has been acquired

  local pkgurl checksum
  pkgurl=$(dep_pkgurl "$dep")
  checksum=$(dep_checksum "$dep")

  local dedup_name is_dedup=false dedup_location # The actual current physical location of the deduplicated package
  if [[ -e ".upkg/.packages" ]] && dedup_location=$(compgen -G ".upkg/.packages/*@$checksum"); then
    # Package already exists in the destination, all we need is the dedup_path so we can symlink it
    $DRY_RUN || processing "Skipping '%s'" "$pkgurl"
    dedup_name=$(basename "$dedup_location")
    is_dedup=true
  else
    ! $DRY_RUN || fatal "'%s' is not installed" "$pkgurl"
    # Obtain package
    dedup_name=$(upkg_download "$dep")
    dedup_location=.upkg/.tmp/root/.upkg/.packages/$dedup_name
  fi

  local dedup_pkgname pkgname
  dedup_pkgname=${dedup_name%@*}

  pkgname="$(jq -re '.name // empty' <<<"$dep")" || pkgname=$dedup_pkgname
  pkgname=$(clean_pkgname "$pkgname")

  local dedup_path=.packages/$dedup_name # The relative path to the deduplicated package from .upkg/
  # Atomic operation, if this fails there is a duplicate
  if ! ln -sT "$dedup_path" "$parent_pkgpath/.upkg/$pkgname" 2>/dev/null; then
    local otherpkg_dedup_pkgname
    otherpkg_dedup_pkgname=$(basename "$(readlink "$parent_pkgpath/.upkg/$pkgname")")
    otherpkg_dedup_pkgname=${otherpkg_dedup_pkgname%@*}
    fatal "conflict: There is more than one package with the name '%s' ('%s' and '%s')" "$pkgname" "$dedup_pkgname" "$otherpkg_dedup_pkgname"
  fi

  if [[ -f $dedup_location && -x $dedup_location ]]; then
    # pkgurl is an executable file (and has been chmod'ed and validated as such in upkg_download), symlink from bin
    upkg_link_cmd "../$dedup_path" "$parent_pkgpath/.upkg/.bin/$pkgname"

  else
    local binpath binpaths=() binpaths_is_default=true
    # Check if there is a bin property in either the dep or in the upkg.json of the package itself
    if jq -re 'has("bin")' <<<"$dep" >/dev/null; then
      readarray -t -d $'\n' binpaths < <(jq -r '.bin[]' <<<"$dep")
      binpaths_is_default=false
    elif [[ -e $dedup_location/upkg.json ]] && jq -re 'has("bin")' "$dedup_location/upkg.json" >/dev/null; then
      readarray -t -d $'\n' binpaths < <(jq -r '.bin[]' "$dedup_location/upkg.json")
      binpaths_is_default=false
    else
      binpaths=(bin)
    fi

    for binpath in "${binpaths[@]}"; do
      if [[ ! -e "$dedup_location/$binpath" ]]; then
        $binpaths_is_default || warning "bin path '%s' in the package '%s' does not exist, ignoring"
        continue
      fi
      if [[ ! -x "$dedup_location/$binpath" ]]; then
        # directories are executable so this works for both files & dirs
        $binpaths_is_default || warning "bin path '%s' in the package '%s' is not executable, ignoring"
        continue
      fi
      local abs_binpath
      abs_binpath=$(realpath "$dedup_location/$binpath")
      if [[ $abs_binpath != "$(realpath "$dedup_location")"/* ]]; then
        warning "bin path '%s' must be a subpath of the package '%s', ignoring" "$binpath" "$pkgurl"
        continue
      fi

      if [[ -f $dedup_location/$binpath ]]; then
        command=$(basename "$binpath")
        upkg_link_cmd "../$dedup_path/$binpath" "$parent_pkgpath/.upkg/.bin/$command"
      else
        for command in "$dedup_location/$binpath"/*; do
          [[ -f "$command" && -x "$command" ]] || continue
          command=$(basename "$command")
          upkg_link_cmd "../$dedup_path/$binpath/$command" "$parent_pkgpath/.upkg/.bin/$command"
        done
      fi
    done
  fi

  ! $DRY_RUN || return 0 # All dependencies of dependencies are locked with checksums, so if we haven't failed already, we won't do if we go deeper
  # Recursively install deps of this package unless it is already dedup'ed
  # Using the pkgname path instead of the dedup path allows us to create dependency tree without checksums
  $is_dedup || upkg_install_deps "$parent_pkgpath/.upkg/$pkgname"
}

upkg_link_cmd() {
  local cmdtarget=$1 cmdpath=$2 other_dedup_path
  mkdir -p "$(dirname "$cmdpath")"
  # Atomic operation. If this fails there is a duplicate command or the same package is depended upon under different names
  if ! ln -sT "$cmdtarget" "$cmdpath" 2>/dev/null; then
    other_dedup_path=$(readlink "$cmdpath")
    if [[ $cmdtarget = "$other_dedup_path" ]]; then
      # Same package different name, this is fine.
      # Continue the loop though, the other install process might have failed on something we linked earlier on
      # Bailing might cause some executables to not be linked
      return 0
    fi
    local targetpkg_dedup_pkgname otherpkg_dedup_pkgname
    # ../.packages/$dedup_pkgname@checksum/bin/$command or ../.packages/$dedup_pkgname@checksum becomes $dedup_pkgname@checksum
    targetpkg_dedup_pkgname=${cmdtarget#'../.packages/'}
    targetpkg_dedup_pkgname=${targetpkg_dedup_pkgname%'/'*}
    targetpkg_dedup_pkgname=${targetpkg_dedup_pkgname%@*}
    # ../.packages/$otherpkg_dedup_pkgname@checksum/bin/$command or ../.packages/$otherpkg_dedup_pkgname@checksum becomes $otherpkg_dedup_pkgname@checksum
    otherpkg_dedup_pkgname=${other_dedup_path#'../.packages/'}
    otherpkg_dedup_pkgname=${otherpkg_dedup_pkgname%'/'*}
    otherpkg_dedup_pkgname=${otherpkg_dedup_pkgname%@*}
    fatal "conflict: '%s' and '%s' both have a command named '%s'" "$targetpkg_dedup_pkgname" "$otherpkg_dedup_pkgname" "$(basename "$cmdpath")"
  fi
}
