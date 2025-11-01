# μpkg - A lightweight package manager for your tooling and operations

If you are tired of running the same `wget | tar xf; chmod` commands every time
you need access to your tooling on a machine or in a container, or you keep
copying the same snippets of code between countless projects, violating DRY
because anything else is not feasible, this is the tool for you.

μpkg and the accompanying [GitHub actions](#github-publishing-actions) securely
automate handling dependencies, [publishing small scripts](#authoring-packages),
and [installing binaries](#installing-single-binaries-to-localbin) without
requiring you to modify your existing infrastructure by virtue of being
limited in scope and light on dependencies (bash, corutils, and jq).

μpkg can install _arbitrary_ tarballs, zipfiles, plain files, and git repositories
for use on your machine or as dependencies to your own tools.

## Contents

- [Dependencies](#dependencies)
- [Installation](#installation)
  - [GitHub action](#github-action)
- [Usage](#usage)
  - [Installing single binaries to `~/.local/bin`](#installing-single-binaries-to-localbin)
  - [Available packages](#available-packages)
  - [Transactionality](#transactionality)
- [Authoring packages](#authoring-packages)
  - [upkg.json](#upkgjson)
  - [Publishing](#publishing)
  - [GitHub publishing actions](#github-publishing-actions)
  - [Using μpkg in bash](#using-μpkg-in-bash)
- [Planned features](#planned-features)
- [Alternatives](#alternatives)

## Dependencies

- bash>=v4.4
- sha256sum (or shasum)
- jq

To install git repos you will need `git` and possibly `ssh`, depending on the
cloning method.

To install files from URLs, you need either `wget` or `curl`. For tarballs you
additionally need `tar` and a decompresser that understands whichever
compression method is used for an archive (often `gzip`).
Zipfiles are decompressed with `unzip`.

To install plain files from the local filesystem no additional dependencies are needed.

## Installation

See [the latest release](https://github.com/orbit-online/upkg/releases/latest)
for the install snippet.

Installation dependencies are `ca-certificates`, `wget`, and `sha256sum`.

For Debian based systems these dependencies are installable with `apt-get install -y ca-certificates wget corutils jq`.  
For alpine docker images use `apk add --update ca-certificates wget bash corutils jq`.  
For Red Hat based systems use `dnf install -y ca-certificates bash corutils wget` (`shasum` is already installed).

Replace `bash ...` with `sudo bash ...` to install system-wide.  
You can also paste the snippet directly into a Dockerfile `RUN` command,
no escaping needed.  
To install to a location other than `$HOME/.local` or `/usr/local` set
`$INSTALL_PREFIX` with `sudo INSTALL_PREFIX=/opt bash ...`.

Have a look at [install.sh](https://github.com/orbit-online/upkg/blob/master/install.sh)
to view a fully commented, non-minified version of this script.

### Install guarantees

The snippet matches the hardcoded checksum against the downloaded install
snapshot, meaning if you copy this script around between e.g. Dockerfiles, you
will always end up with the exact same version of μpkg (or, alternatively, the
install process will fail).

The script also never executes any downloaded code. The install snapshot archive
is downloaded and then extracted. There is no post install execution.  
This is also true for any dependencies that μpkg is told to install, meaning
μpkg can safely be run as root to install scripts/tools that will only be run by
unprivileged users.

### GitHub action

In GitHub workflows you can install μpkg with an action.  
Checkout [orbit-online/upkg-install](https://github.com/orbit-online/upkg-install) for details.

```
jobs:
  compile:
    runs-on: ubuntu-latest
    steps:
    - uses: orbit-online/upkg-install@v1
```

## Usage

```
μpkg - A minimalist package manager
Usage:
  upkg install [-nqv]
  upkg add [-qvgufXB -b PATH... -p PKGNAME -t PKGTYPE] (URL|PATH) [SHA]
  upkg remove [-qnvg] PKGNAME
  upkg list [-qvg] [-- COLUMNOPTS...]
  upkg bundle [-qv -d PATH -p PKGNAME -V VERSION] [PATHS...]

Options:
  -n --dry-run         Dry run, $?=1 if install is required
  -q --quiet           Log only fatal errors
  -v --verbose         Output verbose logs and disable writing to the same line
  -g --global          Act globally
  -u --os-arch         Add os/arch filter of current platform to dependency spec
  -f --force           Replace existing package with the same name
  -X --no-exec         Do not chmod +x the file (implies --no-bin)
  -B --no-bin          Do not link executables in package bin/ to .upkg/.bin
  -b --bin=PATH        Link specified executables or executables in specified
                       directory to .upkg/.bin (default: bin/)
  -t --pkgtype=TYPE    Set the package type (tar, zip, upkg, file, or git)
  -p --pkgname=NAME    Override the package name link in .upkg/
                       (or name property in upkg.json when bundling)
  -d --dest=PATH       Package tarball destination (default: $pkgname.tar.gz)
  -V --pkgver=VERSION  Version of the package that is being bundled
```

### Installing single binaries to `~/.local/bin`

To install tooling globally with μpkg use the `-g` switch.  
By example of [k9s](https://github.com/derailed/k9s):

```
upkg -gp k9s -b k9s https://github.com/derailed/k9s/releases/download/v0.50.6/k9s_Linux_amd64.tar.gz
```

This installs the package `-g`lobally for your user (no `sudo` used, so
installed to `~/.local/bin` instead of `/usr/local/bin`), sets the
`-p`ackagename to `k9s` and specifies the `-b`inary to link as `k9s` in the
archive. If the binary in the archive was located at `k9s_v0.50.6/bin/k9s` you
would change `-b k9s` to `-b k9s_v0.50.6/bin/k9s`.

Note that with the exception of direct file dependencies you cannot alias the
names of the executables.

### Available packages

Check out [PACKAGES.md](PACKAGES.md) for a curated list of available packages.  
You can also use the [`upkg` topic](https://github.com/topics/upkg) to
look for other packages on GitHub.

#### Transactionality

μpkg tries very hard to ensure that either everything is installed/upgraded or
nothing is. Unhandled violations include (and are limited to) broken permissions
on global installs to `bin/`, closure of stderr, or process termination with
`SIGKILL`.

## Authoring packages

### upkg.json

The `upkg.json` file determines your package name, version, executables and
dependencies.

The JSON schema manifest for it is available at `https://schemas.orbit.dev/upkg/upkg-v<VERSION>.schema.json`
and can be used for validation but also for documentation reading in compatible
IDEs.  
Reference it with:

```
{
  "$schema": "https://schemas.orbit.dev/upkg/upkg-v0.28.2.schema.json",
  "name": "pkg-name",
  "dependencies": [
    ...
  ]
}
```

See the schema documentation for an explanation of the various properties.

### Publishing

When hosting a package on GitHub, add the `upkg` topic to make it discoverable
via search.  
Additionally you can send a PR that updates [PACKAGES.md](PACKAGES.md) with a
link to your package.

### GitHub publishing actions

Beyond the GitHub action for [installing μpkg](#github-action) and any
dependencies there are also actions for publishing your own packages:

[orbit-online/upkg-release](https://github.com/orbit-online/upkg-release)
can bundle your package and release it via a GitHub release.

If you'd rather handle the release process yourself you can still use
[orbit-online/upkg-bundle](https://github.com/orbit-online/upkg-bundle)
to bundle your package.

### Using μpkg in bash

#### Including dependencies in bash

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
set -Eeo pipefail; shopt -s inherit_errexit
PKGROOT=$(realpath "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/..")
PATH=$("$PKGROOT/.upkg/.bin/path_prepend" "$PKGROOT/.upkg/.bin")
source "$PKGROOT/.upkg/records.sh/records.sh"

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
3. Setup bash to fail on `$? != 0`, even when piping.  
   Make sure that subshells inherit `set -e` and that functions inherit traps (`set -E`).
4. Determine the package root (the second `realpath` is to resolve the `/..`)
5. Use [path-tools](https://github.com/orbit-online/path-tools) to prepend `.upkg/.bin` (like `PATH=...:$PATH` but if the path already exists it is _moved_ to the front)
6. Include [records.sh](https://github.com/orbit-online/records.sh) for log tooling
7. Rest: Define the function (and call it afterwards)

#### Checking dependencies

For scripts that you don't install via μpkg, checking whether dependencies are
up to date can be done with the `-n` dry-run switch:

```
#!/usr/bin/env bash
PKGROOT=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
(cd "$PKGROOT"; upkg install -qn || {
  printf "my-script.sh: Dependencies are out of date. Run \`upkg install\` in \`%s\`\n" "$PKGROOT" >&2
  return 1
})
```

#### Additional tips for bash scripting

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
`PATH=$("$pkgroot/.upkg/.bin/path_prepend" "$pkgroot/.upkg/.bin")` instead
of `PATH=$pkgroot/.upkg/.bin:$PATH`.

## Planned features

- Using something like `JSON.sh` to avoid the jq dependency
- ~~Describe meta package, depend on a bunch of binaries an symlink them out~~
- Use https://github.com/dominictarr/JSON.sh as fallback
- ~~Add zip support~~
- ~~Check wget support in busybox & alpine~~
- ~~Check mac support~~
- ~~Check freebsd support~~
- ~~Kill running dep installs when first error is discovered~~
- Maybe rethink install_prefix
- Replace '[[...]] ||' with '[[...]] &&'
- Add update property to deps
- update script should update itself first
- update script: pass all arguments as env vars, make the upkg.json entry a single string
- tar: auto-detect whether to --strip-components 1, add strip-components to upkg.json
- ~~Add uname regex filter for packages~~
- Warn when GIT_SSH_COMMAND is set but BatchMode!=yes
- ~~Simulate `ln -T` with `ln -Fi <<<'n'` on BSD~~
- Streamline package names reported in log messages
- Depend on records.sh rather than running our own logging
- ~~Use sha256sum as fallback for shasum -a 256~~
- Add -g switch to install. Allowing upkg.json in $HOME/.local to be tracked by dotfiles trackers
- ~~Depend on upkg.json as a file as a metadata package~~
- ~~Make install script immune to indentation~~
- Document command promotion by specifying binpaths in .upkg/bin
- Reduce the number of dry-run errors that result in `add -f` or `remove` failures
- Add container package type to run containerized utilities
- Don't allow newlines in commands
- Support removing multiple packages at once (`upkg remove PKGNAME...`)

## Alternatives

https://github.com/bpkg/bpkg  
https://github.com/basherpm/basher
