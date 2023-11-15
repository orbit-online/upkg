# μpkg - A minimalist package manager

μpkg is a package manager written in bash with just the bare minimum of features.  
Its primary focus is allowing bash scripts to source dependencies like small
logging functions or commands that shouldn't be tracked with those scripts.

μpkg supports installation to a local project with a `upkg.json` in its root,
and global installation for user- or system-wide usage.

## Contents

- [Dependencies](#dependencies)
- [Installation](#installation)
  - [GitHub action](#github-action)
  - [Upgrading](#upgrading)
- [Usage](#usage)
  - [Silent operation](#silent-operation)
  - [Available packages](#available-packages)
  - [Installing packages without installing μpkg](#installing-packages-without-installing-μpkg)
- [Authoring packages](#authoring-packages)
  - [Publishing](#publishing)
  - [Upgrading](#upgrading)
    - [Transactionality](#transactionality)
  - [Including dependencies](#including-dependencies)
  - [Checking dependencies](#checking-dependencies)
  - [upkg.json](#upkg-json)
    - [dependencies](#dependencies)
    - [files](#files)
    - [commands](#commands)
    - [version](#version)
- [Things that μpkg does not and will not support](#things-that-μpkg-does-not-and-will-not-support)
- [Things that μpkg _might_ support in the future](#things-that-μpkg-might-support-in-the-future)
- [Alternatives](#alternatives)

## Dependencies

- bash>=v4.4
- git
- jq

## Installation

Replace `bash -c ...` with `sudo bash -c ...` to install system-wide.  
You can also paste this directly into a Dockerfile `RUN` command, no escaping needed.

```
bash -ec 'src=$(wget -qO- https://raw.githubusercontent.com/orbit-online/upkg/v0.12.1/upkg.sh); \
shasum -a 256 -c <(printf "866d456f0dcfdb71d2aeab13f6202940083aacb06d471782cec3561c0ff074b0  -") <<<"$src"; \
set - install -g orbit-online/upkg@v0.12.1; eval "$src"'
```

Installation dependencies are `ca-certificates`, `wget`, and `shasum`.

For Debian based systems these dependencies are installable with
`apt-get install -y ca-certificates` (`wget` and `shasum` are already installed).  
For alpine docker images use `apk add --update ca-certificates bash perl-utils`
(`wget` is already installed).  
For Red Hat based systems use `dnf install -y ca-certificates bash perl-utils wget`
(`shasum` is already installed).

### GitHub action

In GitHub workflows you can install μpkg with an action. The action version
also determines the μpkg version that will be installed.

```
jobs:
  compile:
    runs-on: ubuntu-latest
    steps:
    - uses: orbit-online/upkg@<VERSION>
```

### Upgrading

You can upgrade μpkg with μpkg (prefix with `sudo` if installed system-wide):

```
upkg install -g orbit-online/upkg@<VERSION>
```

Use `stable` for `<VERSION>` if you don't care about the specific version number
and would just like to upgrade to the latest stable version.

## Usage

```
μpkg - A minimalist package manager
Usage:
  upkg install [-n] [-g [remoteurl]user/pkg@<version>]
  upkg uninstall -g user/pkg
  upkg list [-g]
  upkg root -g|${BASH_SOURCE[0]}

Options:
  -g  Act globally
  -n  Dry run, $?=1 if install/upgrade is required
```

`upkg install` looks for a `upkg.json` upwards from the current directory and
recursively installs the specified dependencies (see
[dependencies](#dependencies)). Use `-n` to check whether all dependencies are
up-to-date without installing/upgrading anything, note that branch version are
always considered out-of-date (see [Upgrading packages](#upgrading-packages)).

`upkg install -g` installs the specified package and version (either a full git
remote URL or a GitHub user/pkg shorthand) to `/usr/local/lib/upkg` (when root)
or `$HOME/.local` (when not).

`upkg uninstall -g` uninstalls a globally installed package (must be shorthand)
and all its commands (see [commands](#commands)).

`upkg list` shows the installed packages. When using `-g` for "global", package
dependencies are not listed.

`upkg root` is a utility function for scripts in order to build `source` paths
(see [Including dependencies](#including-dependencies)).

### Silent operation

You can suppress processing output by setting `UPKG_SILENT=true`.
When stderr is not a TTY, μpkg switches to outputting a line for each processing
step instead of overwriting the same line.
Errors will always be output and cannot be silenced (use `2>/dev/null` to do
that).

### Available packages

Check out [PACKAGES.md](PACKAGES.md) for a curated list of available packages.  
You can also use the [`upkg` topic](https://github.com/topics/upkg) to
look for other packages on GitHub.

### Installing packages without installing μpkg

If you take a closer look at [how upkg is installed](#installation) you will
notice that `upkg.sh` is the install script for μpkg itself. The three lines
of code do the following:

- Download `upkg.sh`
- Compare the download against the hardcoded checksum
- _Inject the installation parameters for `orbit-online/upkg` as if μpkg was called from the commandline_
- Evaluate the download

With that in mind, you can modify the package name on the third line to install
any package you like. For example:

```
bash -ec 'src=$(wget -qO- https://raw.githubusercontent.com/orbit-online/upkg/v0.12.1/upkg.sh); \
shasum -a 256 -c <(printf "866d456f0dcfdb71d2aeab13f6202940083aacb06d471782cec3561c0ff074b0  -") <<<"$src"; \
set - install -g orbit-online/bitwarden-container@v2023.7.0-4; eval "$src"'
```

_Do note that if the package or any of its dependencies use `upkg root`, things
will break. So the usefulness of this trick might be rather limited._

## Authoring packages

### Publishing

When hosting a package on GitHub, add the `upkg` topic to make it discoverable
via search.  
Additionally you can send a PR that updates [PACKAGES.md](PACKAGES.md) with a
link to your package.

### Upgrading

You can run `upkg install` to upgrade all packages that have a moving version
(i.e. a git branch). It is advisable to use tags or commit hashes as versions
when publishing something that other packages may rely on to avoid bumping past
breaking changes (tags are quickest to install since μpkg can shallow clone the
repo).

All packages that were installed using a commit hash or git tag as the version
and are still referenced with the same version will be skipped during upgrade.
This means a `upkg install` can almost become a no-op and be run automatically
without sacrificing performance. Conversely branch versions will always be
reinstalled, even when they are a dependency of a parent package that is version
pinned via a tag or commit hash.

#### Transactionality

μpkg tries very hard to ensure that either everything is installed/upgraded or
nothing is. Unhandled violations include (and are limited to) broken permissions
(e.g. inconsistent ownership of files), insufficient diskspace, closure of
stderr, or process termination.

### Including dependencies

`upkg root` allows you to avoid the entire "where the heck is my script
installed?" detective work. Simply run `upkg root "${BASH_SOURCE[0]}"` to get
the root install path of your package. You can use this both for sourcing
dependencies and executing them:

```
#!/usr/bin/env bash
# shellcheck source-path=../
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(upkg root "${BASH_SOURCE[0]}")
source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"

my_fn() {
  PATH="$PKGROOT/.upkg/.bin:$PATH"
  if ! do_something "$1"; then
    warning "Failed to do something do_something, trying something else"
    do_something_else "$1"
  fi
}

my_fn "$@"
```

Use `upkg root -g` to get the path to the global installation instead of
hardcoding `$HOME/.local/lib/upkg` or `/usr/local/lib/upkg`.

### Checking dependencies

For scripts that you don't install via μpkg, checking whether dependencies are
up to date can be done with the `-n` dry-run switch:

```
#!/usr/bin/env bash
PKGROOT=$(upkg root "${BASH_SOURCE[0]}")
(cd "$PKGROOT/core"; UPKG_SILENT=true upkg install -n || {
  printf "my-script.sh: Dependencies are out of date. Run \`upkg install\` in \`%s\`\n" "$PKGROOT" >&2
  return 1
})
```

### upkg.json

`upkg.json` has no package name, version or description.
There are 3 config keys you can specify (none are mandatory, but at least one
key _must_ be present).  
It is highly discouraged to specify non-standard keys for your own usage in this
file.

#### dependencies

Dependencies of a package. A dictionary of git cloneable URLs or
GitHub shorthands as keys and git branches/tags/commits as values.

Dependencies will be installed under `.upkg` next to `upkg.json`.

```
{
  ...
  "dependencies": {
    "orbit-online/records.sh": "v0.9.2",
    "git@github.com:andsens/docopt.sh": "v1.0.0-upkg",
    "orbit-online/bitwarden-tools": "master"
  },
  ...
}
```

#### assets

List of files and folders the package consists of. An array of paths relative to
the repository root. Only items listed here and in [commands](#commands) will be
part of the final package installation. All listed paths _must_ exist and
folders _must_ have a trailing slash.

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

#### commands

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
When uninstalling a package these symlinks are removed as well (provided they
still point at the package).

When installing locally, the listed commands will be installed to `.upkg/.bin`.

#### version

This field will be populated by μpkg with the version specified in the global
install command or the dependency specification. It is used to determine whether
an install command should overwrite or skip the package.  
You _must not_ specify it.

```
{
  ...
  "version": "refs/tags/v0.9.2",
  ...
}
```

## Things that μpkg does not and will not support

- `upkg run command` ([modify `$PATH` instead](#including-dependencies))
- `upkg add/remove usr/package@version` to `upkg.json`
- `~`, `^` or other version specifiers ([use branches for that](#upgrading-packages))
- Package version locking
- Package aliases (i.e. non user namespaced package names)

## Things that μpkg _might_ support in the future

- Installing packages via e.g. raw.githubusercontent.com or the local filesystem
  to avoid the git dependency (would require `name` to be present in `upkg.json`)
- Using something like `JSON.sh` to avoid the jq dependency

## Alternatives

https://github.com/bpkg/bpkg  
https://github.com/basherpm/basher
