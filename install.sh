#!/usr/bin/env bash
# shellcheck disable=SC2317

### This is the full version of the minified installation snippet in the README ###

# This script will not be updated with when newer versions of μpkg are released.
# The `echo ...` and `exit 1` are there to prevent users from piping a download
# of this file into bash.
echo "This script is not an install script for μpkg, use the snippet in the README to install μpkg" >&2
exit 1

# The bash part is commented out for nicer syntax highlighting and runnability.
# Run in bash with errexit and pipefail enabled, this basically ensures that any
# errors stop the script from executing further
# bash -eo pipefail <<'INSTALL_UPKG'

# The backslashes and semicolons at the end of the lines have also been removed
# to increase readability.
# They do nothing when pasted into your terminal (other than telling bash that
# everything is one line), but in a Dockerfile this ensures that docker reads
# the line that follows as part of the same RUN command.

# Set the download URL `$u` to the upkg-install.tar.gz install snapshot.
# The contents look like this ():
#   bin/upkg -> ../lib/upkg/.upkg/.bin/upkg
#   lib/upkg/.upkg/.bin/upkg -> ../.packages/upkg.tar@a2f6d1a6c79269a071439f2a414573fa11bec888a673b5b487a9c9e8bfcd8626/bin/upkg
#   lib/upkg/.upkg/.packages/docopt-lib.sh.tar@efab2d2d7efb1e4eae76fd77eea7a0fb524ab7cd441e3b33159ee55ec57d243e/docopt-lib.sh
#   lib/upkg/.upkg/.packages/docopt-lib.sh.tar@efab2d2d7efb1e4eae76fd77eea7a0fb524ab7cd441e3b33159ee55ec57d243e/upkg.json
#   lib/upkg/.upkg/.packages/upkg.tar@a2f6d1a6c79269a071439f2a414573fa11bec888a673b5b487a9c9e8bfcd8626/.upkg/docopt-lib.sh
#   lib/upkg/.upkg/.packages/upkg.tar@a2f6d1a6c79269a071439f2a414573fa11bec888a673b5b487a9c9e8bfcd8626/bin/upkg
#   lib/upkg/.upkg/.packages/upkg.tar@a2f6d1a6c79269a071439f2a414573fa11bec888a673b5b487a9c9e8bfcd8626/lib/add.sh
#   ... more lib files ...
#   lib/upkg/.upkg/.packages/upkg.tar@a2f6d1a6c79269a071439f2a414573fa11bec888a673b5b487a9c9e8bfcd8626/upkg.json
#   lib/upkg/.upkg/upkg -> .packages/upkg.tar@a2f6d1a6c79269a071439f2a414573fa11bec888a673b5b487a9c9e8bfcd8626
#   lib/upkg/upkg.json
# Notice the relative paths. This means that we can install to $HOME/.local, /usr, or /usr/local with the same snapshot
u=https://github.com/orbit-online/upkg/releases/download/v0.20.0/upkg-install.tar.gz

# Hardcoded sha256 checksum `$s` of the install snapshot.
# This ensures that the copied code always installs the same snapshot (or fails if the download URL returns a different snapshot)
c=e3ce4efa9cf939bc58812b443c834a459e11583f9c195b4cc88193f3aec38495

# Create a temporary file `$t` to which we will download the install snapshot
t=$(mktemp)

# Instruct bash to remove the temporary file `$t` when the script exits (regardless of failure or success)
trap 'rm "$t"' EXIT

# Quietly download the snapshot to the temp file `$t` with either wget or curl
# Unlike wget, curl needs to be instructed to fail (-f) and follow redirects (-L)
# We need to follow redirects because GitHub release links redirect to
# https://objects.githubusercontent.com/...
wget -qO"$t" "$u" || curl -fsLo"$t" "$u"

# Using `echo` output the shasum format of "CHECKSUM  FILE" and redirect
# it as a file to the `-c` option of `shasum`. Use `-a 256` to tell it that the
# checksum is sha256.
# Redirect the output to /dev/null, which is just an "OK" on success. Errors
# are output to stderr and will be visible. We rely on the exit code to stop
# the script (see `bash -e` above) if the check fails.
shasum -a 256 -c <(echo "$c  $t")>/dev/null

# Determine the installation prefix `$P`. If `$INSTALL_PREFIX` is set use that,
# otherwise check if we are sudo (`$EUID = 0`), meaning we install to `/usr/local`.
# If we aren't, install to the users home directory in `.local`
P=${INSTALL_PREFIX:-$([[ $EUID = 0 ]] && echo /usr/local || echo "$HOME/.local" )}

# Check if the install prefix `$P` exists, if not we don't need to check whether
# we are overwriting any files. Otherwise list the contents of the snapshot `$t`,
# deselect any directories (exclude any archive entries ending in `/` with `grep`),
# and loop over the files, checking whether any of them exist in `$P`. Fail the
# script if any of the files exist.
# We don't use the `-k` switch from tar ("Don't replace existing files") to
# simply extract the archive because that might result in an incomplete install.
[[ ! -e $P ]] || tar tzf "$t" | grep -v "/$" | while read -r f; do
  [[ ! -e $P/$f ]] || {
    echo "$P/$f already exists">&2
    exit 1
  }
done

# Create the install prefix directory `$P` if it does not already exist.
mkdir -p "$P"

# Extract (x) the compressed (z) snapshot (`-f $t`) to the install prefix (`-C $P`)
tar xz -C "$P" -f "$t"

# Print an empty line to stderr to separate the install snippet from the log output that follows
echo >&2

# Tell the user that μpkg has been installed
echo "μpkg has been installed and can now be invoked with \`upkg'" >&2

# Check if jq is installed and warn the user if not. We don't make this a hard
# error because we might be installing into a chroot or it might be installed
# later.
type jq &>/dev/null || echo "WARNING: \`jq' was not found in \$PATH. jq is a hard dependency."
