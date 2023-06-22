# μpkg - A minimalist package manager

μpkg is a package manager written in <200 lines of bash with just the bare
minimum of features.  
Its primary focus is allowing bash scripts to source dependencies like small
logging functions or commands that shouldn't be tracked with those scripts.

μpkg supports installation to a local project with a `upkg.json` in its root,
and global installation for user- or system-wide usage.

## Contents

- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Upgrading packages](#upgrading-packages)
- [Including dependencies](#including-dependencies)
- [upkg.json](#upkg-json)
  - [dependencies](#dependencies)
  - [files](#files)
  - [commands](#commands)
  - [version](#version)
- [Things that μpkg does not and will not support](#things-that-μpkg-does-not-and-will-not-support)
- [Things that μpkg _might_ support in the future](#things-that-μpkg-might-support-in-the-future)
- [Alternatives](#alternatives)

# Prerequisites

- bash>=v4.4
- git
- jq

## Installation

Replace `bash -c ...` with `sudo bash -c ...` to install system-wide.

```
wget -qO- https://raw.githubusercontent.com/orbit-online/upkg/ft-pin-version/upkg.sh | (
  IFS='' read -r -d $'\0' src; set -e
  printf '%s' "$src" | shasum -a 256 -c <(printf '5c14fe52824acbc0d5af386707df97268b0ff805fcda68bef3cdfc24f19387d1  -')
  bash -c "set - install -g https://github.com/orbit-online/upkg.git@ft-pin-version; $src")
```

## Usage

```
μpkg - A minimalist package manager
Usage:
  upkg install
  upkg install -g [remoteurl]user/pkg@<version>
  upkg uninstall -g user/pkg
  upkg root ${BASH_SOURCE[0]}
```

`upkg install` looks for a `upkg.json` in the current directory and upwards and
recursively installs the specified dependencies (see
[dependencies](#dependencies)).

`upkg install -g` installs the specified package and version (either a full git
remote URL or a GitHub user/pkg shorthand) to `/usr/local/lib/upkg` (when root)
or `$HOME/.local` (when not).

`upkg uninstall -g` uninstalls a globally installed package (must be shorthand)
and all its commands (see [commands](#commands)).

`upkg root` is a utility function for scripts in order to build `source` paths
(see [Including dependencies](#including-dependencies)).

## Upgrading packages

You can run `upkg install` to upgrade all packages that have a moving version
(i.e. a git branch). It is advisable to use commit hashes as versions
when publishing something that other packages may rely on to avoid bumping past
breaking changes.

All packages that were installed using a git tag or commit hash as the version
and are still referenced with the same version will be skipped during upgrade.
This means a `upkg install` can almost become a no-op and be run automatically
without sacrificing performance.

Note: μpkg performs quite a few pre-flight checks before installing or upgrading
a package and its dependencies in order to avoid leaving packages in a broken
state. If it does happen, kindly report a reproduce as an issue.

## Including dependencies

`upkg root` allows you to avoid the entire "where the heck is my script installed"
detective work. Simply run `upkg root "${BASH_SOURCE[0]}"` to get the root
install path of your package. You can use this both for sourcing dependencies
but also executing them:

```
my_fn() {
  set -e
  local pkgroot
  pkgroot=$(upkg root "${BASH_SOURCE[0]}")

  # shellcheck source=.upkg/orbit-online/records.sh/records.sh
  source "$pkgroot/.upkg/orbit-online/records.sh/records.sh"

  PATH="$pkgroot/.upkg/.bin:$PATH"
  command-from-dep "$1"
}

my_fn "$@"
```

## upkg.json

The upkg.json has no package name or description.
There are 3 config keys you can specify (none are mandatory, but at least one
key _must_ be present).

### dependencies

Dependencies of a package. A dictionary of git cloneable URLs or
GitHub shorthands as keys and git branches/tags/commits as values.

Dependencies will be installed under `.upkg` next to `upkg.json`.

```
{
  ...
  "dependencies": {
    "orbit-online/records.sh": "v0.9.2",
    "andsens/docopt.sh": "v1.0.0-upkg",
		"git@github.com:secoya/bitwarden-tools": "master"
  },
  ...
}
```

### assets

List of files and folders the package consists of. An array of paths relative to
the repository root. Only items listed here and in [commands](#commands) will be
part of the final package installation. All listed paths _must_ exist, folders
_must_ have a trailing slash.

```
{
  ...
  "assets": [
    "lib/common.sh",
    "lib/commands.sh",
    "bin/"
  ],
  ...
}
```

### commands

List of commands this package provides. A dictionary of command names as keys
and paths relative to the repository root. Note that the specified files _must_
be marked as executable.

```
{
  ...
  "commands": {
    "parse-spec": "bin/parse.sh",
    "buildit": "bin/build.sh",
    "checkit": "tools/check.sh"
  },
  ...
}
```

When installing globally, the listed commands will be installed as symlinks to
`/usr/local/bin` (when root) or `$HOME/.local/bin` (when not).  
`upkg uninstall -g` uninstalls those symlinks (provided they still point at the
package).

When installing locally, the listed commands will be installed to `.upkg/.bin`.

### version

This field will be populated by μpkg with the version specified in the global
install command or the dependency specification. It is used to determine whether
an install command should overwrite or skip the package. You need not and should
not specify it.

```
{
  ...
  "version": "v0.9.2",
  ...
}
```

## Things that μpkg does not and will not support

- `upkg run command`
- `upkg add/remove usr/package@version`
- `~`, `^` or other version specifiers (use branches for that)
- Package version locking
- Package aliases (i.e. non user namespaced package names)

## Things that μpkg _might_ support in the future

- Installing packages via e.g. raw.githubusercontent.com or the local filesystem
  to avoid the git dependency (would require `name` to be present in `upkg.json`)
- Using something like `JSON.sh` to avoid the jq dependency
- Some kind of index of public packages

## Alternatives

https://github.com/bpkg/bpkg  
https://github.com/basherpm/basher
