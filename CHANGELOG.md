# master

* **feat**: prioritize matches on beginning of words

* **feat**: add keep order option (`-k` `--keep-order`)

  Adds an option to skip sorting of items and preserve the order of lines read
  on stdin.

* **feat**: add plain text option ('-p' '--plain')

  Adds an option to skip the filename match prioritization. Useful when the
  lines are not filepaths.

* **feat**: expose case-sensitive matching in libzf

  Update to the zf algorithm to make matching more precise. Matches on the
  beginning of words are ranked higher.

* **extra**: add shell completions for bash, zsh, and fish

* **fix**: query mangling when moving the cursor left or right

* **fix**: off-by-one scolling error at bottom of terminals

  When zf was run at the bottom of a terminal the scrolling would remove the
  previous prompt.

* **fix**: don't require pressing esc three times to cancel

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
