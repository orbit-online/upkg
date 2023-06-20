# μpkg - A minimalist package manager

μpkg is a package manager written in <200 lines of bash with just the bare
minimum of features.  
Its primary focus is allowing bash scripts to source dependencies like small
logging functions or commands that shouldn't be tracked with those scripts.

μpkg supports installation to a local project with a `upkg.json` in its root,
and global installation for user- or system-wide usage.

## Dependencies

- bash>=v4.4
- git
- jq

## Installation

```
wget -qO- https://raw.githubusercontent.com/orbit-online/upkg/master/upkg.sh |\
(
  src=$(cat)
  [[ $(shasum -a 256 <<<"$src") = '98f5487509716127fa62a7a802ad96ff2ba34606704d0a91de15b6b8955ac132  -' ]] || { echo 'shasum mismatch!'; exit 1; }
  bash -c "set - install -g https://github.com/orbit-online/upkg.git@master; $src"
)
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

When installing a package, μpkg first uninstalls the previous install if it
exists. This means you can simply run `upkg install` to upgrade all packages
that have a moving version (like a branchname). Note that it is advisable to
use commit hashes as versions when publishing something that other packages may
rely on to avoid bumping past breaking changes.

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

The upkg.json has no version, package name, or description.
There are 3 optional config keys in total:

### dependencies

Dependencies of a package. A dictionary of git cloneable URLs or
GitHub shorthands as keys and git branches/tags/commits as values.

Dependencies will be installed under `.upkg` next to `upkg.json`.

```
{
  "dependencies": {
    "orbit-online/records.sh": "v0.9.2",
    "andsens/docopt.sh": "v1.0.0-upkg",
		"git@github.com:secoya/bitwarden-tools": "master"
  },
  ...
}
```

### files

List of files the package consists of. An array of paths relative to the
repository root. Only items listed here or in [commands](#commands) will be
part of the final package installation. All listed paths _must_ exist.

```
{
  ...
  "files": [
    "lib/common.sh",
    "lib/commands.sh"
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

When installing locally, the listed commands will be installed to `/.upkg/.bin`.

## Things that μpkg does not and will not support

- `upkg run command`
- `upkg add/remove usr/package@version`
- `~`, `^` or other version specifiers
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
