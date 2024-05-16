# μpkg - A package manager for your system tooling

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
- [Authoring packages](#authoring-packages)
  - [Publishing](#publishing)
  - [Including dependencies](#including-dependencies)
  - [Checking dependencies](#checking-dependencies)
  - [Additional tips for scripting](#additional-tips-for-scripting)
  - [upkg.json](#upkg-json)
    - [dependencies](#dependencies)
    - [version](#version)
- [Planned features](#planned-features)
- [Alternatives](#alternatives)

## Dependencies

- bash>=v4.4
- shasum
- jq

To install git repos you will need `git` and possibly `ssh`, depending on the
cloning method.

To install files from URLs, you need either `wget` or `curl`. For tarballs you
additionally need `tar` and a library that understand whichever compression
method is used for an archive (often `gzip`).

To install files from the local filesystem you need no additional dependencies
at all.

## Installation

Replace `bash ...` with `sudo bash ...` to install system-wide.  
You can also paste this directly into a Dockerfile `RUN` command, no escaping
needed.  
To install to a location other than `$HOME/.local` or `/usr/local` set
`$INSTALL_PREFIX` with `sudo INSTALL_PREFIX=/opt bash ...`.

Have a look at [install.sh](https://github.com/orbit-online/upkg/blob/master/install.sh)
to view a fully commented and non-minified version of this script.

```
bash -eo pipefail <<'INSTALL_UPKG'
# Read the non-minified and fully documented version on github.com/orbit-online/upkg
u=https://github.com/orbit-online/upkg/releases/download/v0.21.0/upkg-install.tar.gz
c=c01e2cbfb7f9ae05b55cb59d08cd85bc65760b6ab659d3cf36507483d7035dfd;\
t=$(mktemp);trap 'rm "$t"' EXIT;wget -qO"$t" "$u"||curl -fsLo"$t" "$u";shasum \
-a 256 -c <(echo "$c  $t")>/dev/null;P=${INSTALL_PREFIX:-$([[ $EUID = 0 ]]&&\
echo /usr/local||echo "$HOME/.local" )};[[ ! -e $P ]]||tar tzf "$t"|grep -v \
"/$"|while read -r f;do [[ ! -e $P/$f ]]||{ echo "$P/$f already exists">&2;\
exit 1; };done;mkdir -p "$P";tar xz -C "$P" -f "$t";echo>&2;echo "μpkg has \
been installed and can now be invoked with \`upkg'">&2;type jq &>/dev/null\
||echo "WARNING: \`jq' was not found in \$PATH. jq is a hard dependency.">&2\
INSTALL_UPKG
```

### Install dependencies

Installation dependencies are `ca-certificates`, `wget`, and `shasum` (`jq` is
included here so μpkg also works).

For Debian based systems these dependencies are installable with `apt-get install -y ca-certificates wget libdigest-sha-perl jq`.  
For alpine docker images use `apk add --update ca-certificates wget bash perl-utils jq`.  
For Red Hat based systems use `dnf install -y ca-certificates bash perl-utils wget` (`shasum` is already installed).

### Install guarantees

The snippet matches the hardcoded checksum against the downloaded install
snapshot, meaning if you copy this script around between e.g. Dockerfiles, you
will always end up with the exact same version of μpkg (or, alternatively, the
install process will fail).

The script also never executes any downloaded code. The install snapshot archive
is downloaded and then extracted. There is no post install execution.  
This is also true for any dependencies that μpkg is told to install, meaning
μpkg can safely be run as root to install scripts/tools that will only be run as
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
  upkg add [-qvgXB -b PATH... -p PKGNAME -t PKGTYPE] (URL|PATH) [SHA]
  upkg remove [-qnvg] PKGNAME
  upkg list [-qvg] [-- COLUMNOPTS...]
  upkg bundle [-qv -d PATH] -V VERSION [PATHS...]

Options:
  -n --dry-run         Dry run, \$?=1 if install is required
  -q --quiet           Log only fatal errors
  -v --verbose         Output verbose logs and disable writing to the same line
  -g --global          Act globally
  -X --no-exec         Do not chmod +x the file (implies --no-bin)
  -B --no-bin          Do not link executables in package bin/ to .upkg/.bin
  -b --bin=PATH        Link specified executables or contents of specified
                       directory to .upkg/.bin (default: bin/)
  -t --pkgtype=TYPE    Explicitly set the package type (tar, file, or git)
  -p --pkgname=NAME    Override the package name link in .upkg/
  -d --dest=PATH       Package tarball destination (default: \$pkgname.tar.gz)
  -V --pkgver=VERSION  Version of the package that is being bundled
```

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

## Authoring packages

### Publishing

When hosting a package on GitHub, add the `upkg` topic to make it discoverable
via search.  
Additionally you can send a PR that updates [PACKAGES.md](PACKAGES.md) with a
link to your package.

#### Transactionality

μpkg tries very hard to ensure that either everything is installed/upgraded or
nothing is. Unhandled violations include (and are limited to) broken permissions
(e.g. inconsistent ownership of files), closure of stderr, or process
termination.

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

### Checking dependencies

For scripts that you don't install via μpkg, checking whether dependencies are
up to date can be done with the `-n` dry-run switch:

```
#!/usr/bin/env bash
PKGROOT=$(dirname "$(realpath "${BASH_SOURCE[0]}")")
(cd "$PKGROOT"; UPKG_SILENT=true upkg install -n || {
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
`PATH=$("$pkgroot/.upkg/.bin/path_prepend" "$pkgroot/.upkg/.bin")` instead
of `PATH=$pkgroot/.upkg/.bin:$PATH`.

### upkg.json

TODO

## Planned features

- Using something like `JSON.sh` to avoid the jq dependency
- Describe meta package, depend on a bunch of binaries an symlink them out
- Use https://github.com/dominictarr/JSON.sh as fallback
- Add zip support
- Check wget support in busybox & alpine
- Check mac support
- Check freebsd support
- Kill running dep installs when first error is discovered
- Maybe rethink install_prefix
- Replace '[[...]] ||' with '[[...]] &&'
- Add update property to deps
- update script should update itself first
- update script: pass all arguments as env vars, make the upkg.json entry a single string
- tar: auto-detect whether to --strip-components 1, add strip-components to upkg.json
- Add uname regex filter for packages
- Warn when GIT_SSH_COMMAND is set but BatchMode!=yes
- Simulate `ln -T` with `ln -Fi <<<'n'` on BSD
- Streamline package names are reported in log messages
- Depend on records.sh rather than running our own logging
- Use sha256sum as fallback for shasum -a 256
- Add -g switch to install. Allowing upkg.json in $HOME/.local to be tracked by dotfiles trackers

## Alternatives

https://github.com/bpkg/bpkg  
https://github.com/basherpm/basher
