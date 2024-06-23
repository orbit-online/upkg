#!/usr/bin/env bash
# shellcheck source-path=..
set -Eeo pipefail; shopt -s inherit_errexit nullglob

# Install all packages referenced upkg.json, remove existing ones that aren't, then do the same for their command symlinks
upkg_install() {
  # writability of .upkg/ itself has already been established by upkg_mktemp
  [[ ! -e .upkg/.packages || -w .upkg/.packages  ]] || fatal "'%s' is not writeable" "$INSTALL_PREFIX/bin"
  if $is_global; then
    if [[ -e $INSTALL_PREFIX/bin ]]; then
      [[ -w $INSTALL_PREFIX ]] || \
        fatal "'%s' is not writeable by the current user, will not be able to create %s/bin" "$INSTALL_PREFIX" "$INSTALL_PREFIX"
    elif [[ -w $INSTALL_PREFIX/bin ]]; then
        fatal "'%s' is not writeable by the current user, will not be able to remove/symlink executables" "$INSTALL_PREFIX/bin"
    fi
  fi

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
          "$cmd" "$INSTALL_PREFIX/bin" "$INSTALL_PREFIX/lib/upkg/.upkg/.bin"
    done
  fi

  if ! $DRY_RUN; then
    if [[ -e .upkg/.tmp/root/.upkg/.packages ]]; then
      # .bin/ and all symlinks in .upkg/ are fully rebuilt during install, so we just replace everything
      rm -rf .upkg/.bin
      rm -f .upkg/* # "*" works here because we don't have nullglob on and dotglob off, meaning don't match .packages/ and .tmp/
      # Move all command links
      [[ ! -e .upkg/.tmp/root/.upkg/.bin ]] || mv -nt .upkg/ .upkg/.tmp/root/.upkg/.bin
      # Move all direct package dependencies
      mv -nt .upkg .upkg/.tmp/root/.upkg/*

      local dedup_dir new_dedup_dir
      # Check if there are packages in .upkg/.tmp/root/.upkg/.packages/ that do not exist in .upkg/
      # Meaning there are new dependencies
      for new_dedup_dir in .upkg/.tmp/root/.upkg/.packages/*; do
        dedup_dir=.upkg/.packages/$(basename "$new_dedup_dir")
        if [[ ! -e $dedup_dir ]]; then
          mkdir -p .upkg/.packages
          # Move the new package
          mv -nt .upkg/.packages "$new_dedup_dir"
        elif [[ ! -L "$new_dedup_dir" ]]; then
          # This should never happen, it means that upkg_install_dep didn't detect an already dedup'ed package
          fatal "INTERNAL ERROR: '%s' was not dedup'ed"
        else
          # Cleanup the deduplication symlink
          rm "$new_dedup_dir"
        fi
      done

      # Remove all unreferenced packages
      # all pkgs - referenced pkgs = unreferenced pkgs
      local unreferenced_pkgs
      readarray -t -d $'\n' unreferenced_pkgs < <(comm -23 \
        <(for pkg in .upkg/.packages/*; do printf "%s\n" "$pkg"; done | sort) \
        <(upkg_list_referenced_pkgs . | sort )
      )

      for dedup_dir in "${unreferenced_pkgs[@]}"; do
        [[ -n $dedup_dir ]] || continue # See above
        # Remove dedup package that is no longer referenced by any dependency
        rm -rf "$dedup_dir"
      done
    else
      # The install resulted in all deps being removed. Don't keep the .upkg/ dir around
      rm -rf .upkg
    fi

  else
    local dedup_link new_dedup_link
    # Check if the linked packages in .upkg/ are different from the ones .upkg/.tmp/root/.upkg/
    # This means a dependency has been removed or changed
    for dedup_link in .upkg/*; do
      new_dedup_link=.upkg/.tmp/root/.upkg/$(basename "$dedup_link")
      if [[ -e $new_dedup_link ]]; then
        if [[ $(readlink "$dedup_link") != $(readlink "$new_dedup_link") ]]; then
          dry_run_error "The dependency '%s' has changed" "$(basename "$dedup_link")"
        else
          # Cleanup the dedup link in .upkg/.tmp/root/.upkg/ so the loop below can be simpler
          rm "$new_dedup_link"
        fi
      else
        dry_run_error "'%s' is no longer depended upon or has changed" "$(basename "$dedup_link")"
      fi
    done

    # Check if there are links remaining in .upkg/.tmp/root/.upkg/
    # This means a dependency to an existing dedup package has been added
    for new_dedup_link in .upkg/.tmp/root/.upkg/*; do
      new_dedup_link=.upkg/$(basename "$new_dedup_link")
      dry_run_error "'%s' is a new dependency" "$(basename "$new_dedup_link")"
    done

    local bin_dest new_bins=() unreferenced_bins=()
    # installed bins - current bins = new bins
    # current bins - installed bins = unreferenced bins
    readarray -t -d $'\n' unreferenced_bins < <(comm -23 <(upkg_resolve_links .upkg/.bin) <(upkg_resolve_links .upkg/.tmp/root/.upkg/.bin))
    for bin_dest in "${unreferenced_bins[@]}"; do
      [[ -n $bin_dest ]] || continue # See above
      dry_run_error "'%s' is not linked to right package from .upkg/.bin" "$(basename "$bin_dest")"
    done
    readarray -t -d $'\n' new_bins < <(comm -13 <(upkg_resolve_links .upkg/.bin) <(upkg_resolve_links .upkg/.tmp/root/.upkg/.bin))
    for bin_dest in "${new_bins[@]}"; do
      [[ -n $bin_dest ]] || continue # See above
      dry_run_error "'%s' is not linked from .upkg/.bin" "$(basename "$bin_dest")"
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
      if $DRY_RUN; then
        dry_run_error "'%s' was not symlinked" "$INSTALL_PREFIX/bin/$cmd"
      else
        processing "Linking '%s'" "$cmd"
        mkdir -p "$INSTALL_PREFIX/bin"
        ln -sT "../lib/upkg/.upkg/.bin/$cmd" "$INSTALL_PREFIX/bin/$cmd"
      fi
    done

    # available - global = old links
    local removed_links=()
    readarray -t -d $'\n' removed_links < <(comm -13 <(printf "%s\n" "$available_cmds") <(printf "%s\n" "$global_cmds"))
    for cmd in "${removed_links[@]}"; do
      [[ -n $cmd ]] || continue # See above
      # Remove all old links
      if $DRY_RUN; then
        dry_run_error "'%s' should not be symlinked" "$INSTALL_PREFIX/bin/$cmd"
      else
        rm "$INSTALL_PREFIX/bin/$cmd"
      fi
    done
  fi
}

# Install all dependencies of a package
upkg_install_deps() {
  local pkgpath=$1 deps=()

  # Loads of early returns here
  [[ -e $pkgpath/upkg.json ]] || return 0 # No upkg.json -> no deps -> nothing to do
  readarray -t -d $'\n' deps < <(jq -rc '(.dependencies // [])[]' "$pkgpath/upkg.json")
  [[ ${#deps[@]} -gt 0 ]] || return 0 # No deps -> nothing to do
  mkdir "$pkgpath/.upkg" 2>/dev/null || return 0 # .upkg exists -> another process is already installing the deps

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
      until [[ -e $pkgpath/.upkg/.sentinels/$dep_idx.lock || -e $pkgpath/.upkg/.sentinels/$dep_idx.fail ]]; do sleep .01; done
    fi
    # checksums are not unique across dependencies, so we use the dependencies array order as a key instead
    : $((dep_idx++))
  done

  dep_idx=0
  for dep in "${deps[@]}"; do
    # Wait for each lock sentinel to exist
    until [[ -e $pkgpath/.upkg/.sentinels/$dep_idx.lock || -e $pkgpath/.upkg/.sentinels/$dep_idx.fail ]]; do sleep .01; done
    : $((dep_idx++))
  done

  # All install processes have acquired the shared lock, we can now wait for all shared locks to be released
  exec 8<>"$pkgpath/upkg.json"; flock -x 8

  # All processes have either succeeded or failed, check the result
  dep_idx=0
  for dep in "${deps[@]}"; do
    # Check that no processes failed
    [[ ! -e $pkgpath/.upkg/.sentinels/$dep_idx.fail ]] || \
      fatal "An error occurred while installing '%s'" "$(dep_pkgurl "$dep")"
    if [[ -e "$pkgpath/.upkg/.sentinels/$dep_idx.dry-run-fail" ]]; then
      # We don't descend into dependencies during dry-run
      # Meaning we are not in a backgrounded subshell, meaning setting this will have an effect
      # shellcheck disable=SC2034
      DRY_RUN_EXIT=1
    fi
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

  local pkgurl checksum pkgtype
  pkgurl=$(dep_pkgurl "$dep")
  checksum=$(dep_checksum "$dep")
  pkgtype=$(dep_pkgtype "$dep")

  local dedup_name dedup_glob is_dedup=false
  if [[ -e .upkg/.packages ]]; then
    case "$pkgtype" in
    tar)  dedup_glob=".upkg/.packages/*.tar@$checksum" ;;
    zip)  dedup_glob=".upkg/.packages/*.zip@$checksum" ;;
    upkg) dedup_glob=".upkg/.packages/*.upkg.json@$checksum" ;;
    file) if dep_is_exec "$dep"; then dedup_glob=".upkg/.packages/*+x@$checksum"
          else                        dedup_glob=".upkg/.packages/*-x@$checksum"
          fi ;;
    git)  dedup_glob=".upkg/.packages/*.git@$checksum" ;;
    esac

    if dedup_name=$(compgen -G "$dedup_glob"); then
      dedup_name=${dedup_name%%$'\n'*} # Get the first result if compgen returns multiple, should never happen
      dedup_name=$(basename "$dedup_name")
      # Package already exists in the destination, symlink it
      $DRY_RUN || verbose "Skipping download of '%s'" "$pkgurl"
      is_dedup=true

      mkdir -p .upkg/.tmp/root/.upkg/.packages
      # Place a symlink to the proper physical location of the dedup'ed package in the root package
      # If this fails, some other install process already linked it. Also, I counted the ../'es, they're all there, don't worry
      ln -sT "../../../../.packages/$dedup_name" ".upkg/.tmp/root/.upkg/.packages/$dedup_name" 2>/dev/null || true
    fi
  fi

  if ! $is_dedup; then
    if $DRY_RUN; then
      touch "$parent_pkgpath/.upkg/.sentinels/$dep_idx.dry-run-fail"
      dry_run_error "'%s' is not installed" "$pkgurl"
      return 1
    fi
    # Obtain package
    # No need to link here like we did when we dedup'ed. upkg_download() places the physical package in the root package
    dedup_name=$(upkg_download "$dep")
  fi

  local dedup_path=.upkg/.tmp/root/.upkg/.packages/$dedup_name dedup_pkgname dep_upkgjson pkgname
  dedup_pkgname=${dedup_name%@*}
  local dep_upkgjson
  dep_upkgjson=$(cat "$dedup_path/upkg.json" 2>/dev/null || printf '{}')
  # Calculate the pkgname independently from what the dedup package is named.
  # Two or more pkgurls may have the same shasum, in which case upkg_download will only download one and return that
  # dedup_name for the others and we want the basename for each URL as the pkgname. This only applies to packages
  # whose pkgnames are derived from the URL (i.e. not applicable when overriding names or upkg.json has a name specified)
  pkgname=$(get_pkgname "$dep" "$dep_upkgjson" true)

  local packages_path
  if [[ $pkgpath = .upkg/.tmp/root ]]; then
    # The root package has .packages placed as a sibling to the package aliases
    packages_path=.packages
  else
    # All packages are physically placed in .upkg/.packages of the root pkg, so this symlink will resolve
    packages_path=../..
  fi

  # Atomic operation, if this fails there is a duplicate
  if ! ln -sT "$packages_path/$dedup_name" "$parent_pkgpath/.upkg/$pkgname" 2>/dev/null; then
    local otherpkg_dedup_pkgname
    otherpkg_dedup_pkgname=$(basename "$(readlink "$parent_pkgpath/.upkg/$pkgname")")
    otherpkg_dedup_pkgname=${otherpkg_dedup_pkgname%@*}
    fatal "conflict: There is more than one package with the name '%s' ('%s' and '%s')" "$pkgname" "$dedup_pkgname" "$otherpkg_dedup_pkgname"
  fi

  if [[ -f $dedup_path && -x $dedup_path ]]; then
    if ! jq -re 'has("bin")' <<<"$dep" >/dev/null; then
      # pkgurl is an executable file and linking to .bin has not been disabled
      upkg_link_cmd "../$packages_path/$dedup_name" "$parent_pkgpath/.upkg/.bin/$pkgname"
    fi

  else
    # All dependencies of dependencies are locked with checksums, so during a dry-run if we haven't failed already,
    # we won't if we go deeper either. For packages are dedup'ed we have already done the work.
    if ! $DRY_RUN && ! $is_dedup; then
      # Recursively install deps of this package unless it is already dedup'ed
      # Using the pkgname path instead of the dedup path allows us to create dependency tree without checksums
      upkg_install_deps "$parent_pkgpath/.upkg/$pkgname"
    fi

    local binpath binpaths=(bin) binpaths_is_default=true
    # Check if there is a bin property in either the dep or in the upkg.json of the package itself
    if jq -re 'has("bin")' <<<"$dep" >/dev/null; then
      readarray -t -d $'\n' binpaths < <(jq -r '.bin[]' <<<"$dep")
      binpaths_is_default=false
    elif [[ -e $dedup_path/upkg.json ]] && jq -re 'has("bin")' "$dedup_path/upkg.json" >/dev/null; then
      readarray -t -d $'\n' binpaths < <(jq -r '.bin[]' "$dedup_path/upkg.json")
      binpaths_is_default=false
    fi

    for binpath in "${binpaths[@]}"; do
      if [[ ! -e $dedup_path/$binpath ]]; then
        $binpaths_is_default || warning "bin path '%s' in the package '%s' does not exist, ignoring" "$binpath" "$pkgurl"
        continue
      fi
      if [[ ! -x $dedup_path/$binpath ]]; then
        # directories are executable so this works for both files & dirs
        $binpaths_is_default || warning "bin path '%s' in the package '%s' is not executable, ignoring" "$binpath" "$pkgurl"
        continue
      fi

      local resolved_binpath
      resolved_binpath=$(realpath "$dedup_path/$binpath")

      if [[ $resolved_binpath != "$(realpath "$PWD/.upkg")"/* ]]; then
        warning "bin path '%s' must be located in the package '%s', ignoring" "$binpath" "$pkgurl"
        continue
      fi

      if [[ -f $dedup_path/$binpath ]]; then
        command=$(basename "$binpath")
        upkg_link_cmd "../$packages_path/$dedup_name/$binpath" "$parent_pkgpath/.upkg/.bin/$command"
      else
        for command in "$dedup_path/${binpath%'/'}"/*; do
          [[ -f $command && -x $command ]] || continue
          command=$(basename "$command")
          upkg_link_cmd "../$packages_path/$dedup_name/${binpath%'/'}/$command" "$parent_pkgpath/.upkg/.bin/$command"
        done
      fi
    done
  fi
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
