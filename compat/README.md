# `upkg-compat` - Compatibility layer for μpkg v0.13.0

This is a compatibility layer enabling a seamless transition between μpkg
v0.13.0 and v0.20.0+. `upkg-compat` takes over the `upkg` binary symlink and
switches between v0.13.0 and v0.20.0+ depending on the arguments given or the
format of `upkg.json` in the current directory.

## Installation

```
sudo bash -c 'wget -qO>(tar xzC /usr/local) https://github.com/orbit-online/upkg/releases/latest/download/upkg-compat-install.tar.gz'
```
