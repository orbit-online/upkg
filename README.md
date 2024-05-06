TODO:
Describe meta package, depend on a bunch of binaries an symlink them out
Use https://github.com/dominictarr/JSON.sh as fallback
Add zip support
Check wget support in busybox & alpine
Check mac support
Check freebsd support
Add test check that determines unused snapshots
Kill running dep installs when first error is discovered
Maybe rethink install_prefix
Replace '[[...]] ||' with '[[...]] &&'
Add #update-cmd=
update script should update itself first
update script: pass all arguments as env vars, make the upkg.json entry a single string
tar: auto-detect whether to --strip-components 1, add strip-components to upkg.json
Figure out a way to check if a package is installed

## Testing

diff --color=always -u --label expected --label actual tests/snapshots/package-templates.files <(cd tests/package-templates; tree -n -p --charset=UTF-8 -a -I .git .)

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
  - [Additional tips for scripting](#additional-tips-for-scripting)
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
bash -ec 'src=$(wget -qO- https://raw.githubusercontent.com/orbit-online/upkg/v0.14.0/upkg.sh); \
shasum -a 256 -c <(printf "8312d0fa0e47ff22387086021c8b096b899ff9344ca8622d80cc0d1d579dccff  -") <<<"$src"; \
set - install -g orbit-online/upkg@v0.14.0; eval "$src"'
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

1. Download `upkg.sh`
2. Compare the download against the hardcoded checksum
3. _Inject the installation parameters for `orbit-online/upkg` as if μpkg was called from the commandline_
4. Evaluate the download

With that in mind, you can modify the package name from point #3 and on the
third line to install any package you like. For example:

```
bash -ec 'src=$(wget -qO- https://raw.githubusercontent.com/orbit-online/upkg/v0.14.0/upkg.sh); \
shasum -a 256 -c <(printf "8312d0fa0e47ff22387086021c8b096b899ff9344ca8622d80cc0d1d579dccff  -") <<<"$src"; \
set - install -g orbit-online/bitwarden-tools@v1.4.9; eval "$src"'
```

You can also install dependencies for a script with an accompanying `upkg.json`
that you copied into e.g. a docker image like this:

```
COPY upkg.json /service
COPY --chmod=0755 my-script.sh /service
bash -ec 'src=$(wget -qO- https://raw.githubusercontent.com/orbit-online/upkg/v0.14.0/upkg.sh); \
shasum -a 256 -c <(printf "8312d0fa0e47ff22387086021c8b096b899ff9344ca8622d80cc0d1d579dccff  -") <<<"$src"; \
set - install; eval "$src"'
```

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

To determine the package root path use `${BASH_SOURCE[0]}`.  
Use `realpath` to ensure that symlinks and relative paths are resolved.

```
PKGROOT=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
```

Alternatively you can use a short `until` loop to find the ancestor directory that contains `upkg.json`.  
This way you can move the script around without having to adjust the relative path:

```
until [[ -e $PKGROOT/upkg.json || $PKGROOT = '/' ]]; do PKGROOT=$(dirname "${PKGROOT:-$(realpath "${BASH_SOURCE[0]}")}"); done
```

Here's an example of a short script with a useful preamble:

```
#!/usr/bin/env bash
# shellcheck source-path=../
set -eo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
PATH=$("$PKGROOT/.upkg/.bin/path_prepend" "$PKGROOT/.upkg/.bin")
source "$PKGROOT/.upkg/orbit-online/records.sh/records.sh"

my_fn() {
  if ! do_something "$1"; then
    warning "Failed to do something do_something, trying something else"
    do_something_else "$1"
  fi
}

my_fn "$@"
```

The following things are happening here (line-by-line):

1. Bash shebang
2. Inform shellcheck about the package root so it can follow `source` calls
3. Setup bash to fail on `$? != 0`, even when piping. Make sure that subshells inherit `set -e`.
4. Determine the package root (the second `realpath` is to resolve the `/..`)
5. Use [path-tools](https://github.com/orbit-online/path-tools) to prepend `.upkg/.bin` (like `PATH=...:$PATH` but if the path already exists it is _moved_ to the front)
6. Include [records.sh](https://github.com/orbit-online/records.sh) for log tooling
7. Rest: Define the function (and call it afterwards)

### Checking dependencies

For scripts that you don't install via μpkg, checking whether dependencies are
up to date can be done with the `-n` dry-run switch:

```
#!/usr/bin/env bash
PKGROOT=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
(cd "$PKGROOT/core"; UPKG_SILENT=true upkg install -n || {
  printf "my-script.sh: Dependencies are out of date. Run \`upkg install\` in \`%s\`\n" "$PKGROOT" >&2
  return 1
})
```

### Additional tips for scripting

When creating scripts not installed via μpkg, use
`PKGROOT=$HOME/.local/lib/upkg; [[ $EUID != 0 ]] || PKGROOT=/usr/local/lib/upkg`
to get the path to the global installation.

Use `local pkgroot; pkgroot=$(dirname "$(realpath "${BASH_SOURCE[0]}")")`
inside your function if you are building a library (as opposed to a command)
to avoid `$PKGROOT` being overwritten by external code.

You only need to specify `# shellcheck source-path=` if your script is not
located in `$pkgroot` (`source-path` is `./` by default).

If you are calling scripts from the same package consider using
[path-tools](https://github.com/orbit-online/path-tools) to avoid prepending
the same `.upkg/bin` PATH multiple times (i.e. use
`PATH=$("$pkgroot/.upkg/.bin/path_prepend" "$pkgroot/.upkg/.bin")` instead).

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
