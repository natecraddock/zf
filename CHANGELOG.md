# master

# v0.2

This release fixes a few minor bugs, optimizes drawing the terminal user
interface, and introduces a number of new features:

* **feat**: add `libzf` ffi library

  Exposes the zf ranking algorithm to be used as a library. See
  [natecraddock/telescope-zf-native.nvim](https://github.com/natecraddock/telescope-zf-native.nvim)
  for an example neovim plugin that uses libzf.

* **feat**: match highlights

  The results are now highlighted to show the substrings that match the query
  tokens.

* **feat**: drop semver.

  Once v1.0 is released, the commandline argument api will be stabilized. Any
  changes to flags will require a major version increment. Any fixes and
  non-breaking features are considered minor releases.

* **break**: rename `--query` flag to `--filter`

  This makes more sense, and is compatible with fzf. It also makes it possible
  to support a `--query` flag in the future if needed.

* **feat**: add `--lines [num lines]` option

  Allows controlling the number of displayed result lines in the terminal user
  interface.

# v0.0.1

Initial release
