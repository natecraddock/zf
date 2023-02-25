# master

* **feat**: add multiselect support
  ([e19409](https://github.com/natecraddock/zf/commit/b414ad))

  Adds the ability to select and deselect candidates. Selection is toggled with <kbd>Tab</kbd>. The selected line is moved down with <kbd>Tab</kbd>, and moved up with <kbd>Shift Tab</kbd>. If any lines are selected, the number selected is displayed in the top
  right of the UI.

  Lines are written to stdout separated by newlines. This may be configurable in the future.

* **feat**: allow scrolling the list of candidates
  ([4ea08e](https://github.com/natecraddock/zf/commit/b414ad))

  When the list of candidates is larger than the terminal height or configured display lines (default 10), moving the selected line past the bottom will now scroll the list. This means any item can be selected with the arrow keys alone.

# 0.7.0

The headline feature of this release is strict path matching, another way that zf is optimized for filtering filepaths with accuracy and precision.

With strict path matching, when a query token contains a `/` character, any other characters after the slash must appear in a single path segment. As an example, the query `/foo` would match `/foo/bar/` but not `/fo/obar` because the characters `"foo"` must appear in a single path segment.

This is useful for narrowing down results when you know the exact path structure of your files. As a more complex example, with the following paths

```
app/models/foo/bar/baz.rb
app/models/foo/bar-baz.rb
app/models/foo-bar-baz.rb
app/monsters/dungeon/foo/bar/baz.rb
```

The query `a/m/f/b/baz` filters to only `app/models/foo/bar/baz.rb` whereas in previous versions of zf the string `app/monsters/dungeon/foo/bar/baz.rb` is also included in the results. To end strict path matching, just add a space to start a new token.

This release also includes many fixes, refactors, optimizations, unicode support, and a few other small features. Here's an overview of the biggest changes:

* **feat**: strict path matching
  ([b414ad](https://github.com/natecraddock/zf/commit/b414ad))

* **feat**: unicode support
  ([3e7069](https://github.com/natecraddock/zf/commit/3e7069))
  ([d596cc](https://github.com/natecraddock/zf/commit/d596cc))
  ([b397fa](https://github.com/natecraddock/zf/commit/b397fa))

  Zf now normalizes all input (both the lines read on `stdin` and the query text) to unicode NFD form. This improves matching accuracy. The query editing line also now fully supports unicode grapheme cluster editing.

* **feat**: add `ZF_HIGHLIGHT` environment variable to set highlight color
  ([3cf713](https://github.com/natecraddock/zf/commit/3cf713))

  Adds a new environment variable to set the highlight color. Valid colors are: `black`, `red`, `green`, `yellow`, `blue`, `magenta`, `cyan`, `white`, `bright_black`, `bright_red`, `bright_green`, `bright_yellow`, `bright_blue`, `bright_magenta`, `bright_cyan`, and `bright_white`

* **perf**: preallocate filtered candidate buffers
  ([c2a36ba](https://github.com/natecraddock/zf/commit/c2a36ba))

  Because zf uses an arena allocator and does not deallocate, this prevents unnecessary allocations. Zf no longer has memory use increase over the runtime of the program. This also slightly improves performance by reducing time spent allocating.

* **tests**: add initial zf ranking consistency tests
  ([fbfb8f](https://github.com/natecraddock/zf/commit/fbfb8f))


* **fix**: escape ANSI codes in `ZF_PROMPT`
  ([e0118d](https://github.com/natecraddock/zf/commit/e0118d))

  This adds SGR ANSI escape code handling to `ZF_PROMPT`. It now correctly calculates the width of the prompt when ANSI codes are included. Currently only supports the SGR codes

* **fix**: correctly calculate the width of unicode in `ZF_PROMPT`
  ([c426ac](https://github.com/natecraddock/zf/commit/c426ac))

* **fix**: highlights incorrect when a candidate ends in a `/` character
  ([1d8924](https://github.com/natecraddock/zf/commit/1d8924))

# 0.6.0

This release is focused on small optimizations, refactors, and using zf as a library. Because zf is now packaged as a Zig library, it makes sense to switch back to semantic versioning which makes this version 0.6.0 rather than 0.6. This release also updates the source code to support Zig 0.10.0.

While refactoring zf to be more easily consumed by a library, I designed the library to require zero allocations and be passed external slices of memory. Alongside this I also added a restriction to zf as a cli tool. The number of space-separated tokens in the query is now limited to 16. This seems like a safe upper limit, but can be raised if needed.

* **library**: package zf as a Zig library
  ([47467d](https://github.com/natecraddock/zf/commit/47467d))
  ([f9f17d](https://github.com/natecraddock/zf/commit/f9f17d))

  Adds a Zig package exposing the zf ranking and highlight functions. Also updates the existing C library to match the Zig library.

  See the [docs](https://github.com/natecraddock/zf/blob/master/doc/zf.md) for instructions on using Zf as a library.

* **refactor**: reduce size of the Candidate struct and reorganize code
  ([ee2d18](https://github.com/natecraddock/zf/commit/ee2d18))
  ([f88c76](https://github.com/natecraddock/zf/commit/f88c76))
  ([426f4d](https://github.com/natecraddock/zf/commit/426f4d))

  A small optimization that reduces the size of the Candidate struct. This involved a restructure of the ranking algorithm, separating ranking and highlighting into two separate functions. This resulted in a small but measurable performance increase.

* **ci**: zf tests are now run with GitHub actions for pushes and PRs
  ([41eaa5](https://github.com/natecraddock/zf/commit/41eaa5))

# 0.5

This smaller release fixes a few bugs and adds support for a few environment variables.
A long time coming (I've been focused on other projects), I'm finally back to work on zf. The next release will be focused on utf-8 unicode support.

* **feat**: `ZF_PROMPT` environment variable
  ([7c6b0a](https://github.com/natecraddock/zf/commit/7c6b0a))

  Allows customization of the zf prompt. Note that this does not yet support
  unicode characters. If you want a space displayed after the prompt, you must
  include it in the string. For example: `export ZF_PROMPT="> "`.

* **feat**: `ZF_VI_MODE` environment variable
  ([ca05d3](https://github.com/natecraddock/zf/commit/ca05d3))

  Adds an environment variable that changes the behavior of the ctrl+k
  binding. When enabled (the variable is present and is not empty) ctrl+k
  moves up a line. When disabled, ctrl+k acts like readline and deletes
  from the cursor to the end of the line.

* **feat**: `NO_COLOR` environment variable
  ([541052](https://github.com/natecraddock/zf/commit/541052))

  Support the semi-standardized `NO_COLOR` environment variable to disable
  terminal colors.

  See https://no-color.org

* **fix**: missing null check
  ([783441](https://github.com/natecraddock/zf/commit/783441b))

  The name field was assumed to be not null so using the --plain option caused
  a crash. Caught in telescope-zf-native.nvim

* **fix**: trailing chars on TUI stdout
  ([6a717d](https://github.com/natecraddock/zf/commit/6a717d19))

  The buffer wasn't flushed properly, leading to the buffered lines of cleanup
  print statements never being output.

* **fix**: crash when highlight ranges extend past terminal width
  ([bf437f](https://github.com/natecraddock/zf/commit/bf437f))

  When a highlight range extended past the width of the terminal the slice
  would go out of bounds causing a panic.

# 0.4

This release includes many refactors and cleanups to the code. Flicker in
drawing the UI has been resolved, and work has begun on macOS support. And
finally, the algorithm for matching on filenames has received an update and
should be even more precise.

Commit hashes are now included in the changelog for convenience.

* **feat**: increase ranking algorithm precision
  ([d31e70](https://github.com/natecraddock/zf/commit/d31e70))

  Matches on filenames are now given a rank priority relative to the percentage
  of the filename matched. As more query term letters match the filename, the
  higher it ranks.

* **feat**: draw count information in the query line
  ([6aa45e](https://github.com/natecraddock/zf/commit/6aa45e))

  Display a [filtered count]/[total count] indicator on the right side of the
  query line. Currently this is enabled and cannot be toggled, but a flag will
  be added soon.

* **feat**: add more readline bindings ([@jmbaur](https://github.com/jmbaur))
  ([9c7a78](https://github.com/natecraddock/zf/commit/9c7a78))

* **feat**: add `ctrl-j` and `ctrl-k` mappings
  ([3fb459](https://github.com/natecraddock/zf/commit/3fb459))

* **feat**: switch from bright blue to cyan for highlights
  ([ee05d3](https://github.com/natecraddock/zf/commit/ee05d3))

* **fix**: delete keybinding
  ([cbb467](https://github.com/natecraddock/zf/commit/cbb467))

* **fix**: remove flicker in the TUI
  ([cc7c2c](https://github.com/natecraddock/zf/commit/cc7c2c))

  The default TTY writer was not buffered. Buffering the output reduces syscalls
  and makes the TUI much more responsive!

* **fix**: emit DECCKM "application mode" escape sequences
  ([@ratfactor](https://github.com/ratfactor))
  ([d2c795](https://github.com/natecraddock/zf/commit/d2c795))

* **fix**: failure to render TUI on macOS
  ([9ade19](https://github.com/natecraddock/zf/commit/9ade19))

  macOS support is still not official, but should work better now.

# 0.3

This release improves the ranking algorithm, adds two new commandline options,
fixes a few bugs, and optimizes the TUI drawing code. Shell completion scripts
are now provided for bash, zsh, and fish.

* **feat**: prioritize matches on beginning of words

  Matches that begin at the start of a word will be ranked higher than matches
  in the middle of a word.

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

* **fix**: off-by-one scrolling error at bottom of terminals

  When zf was run at the bottom of a terminal the scrolling would remove the
  previous prompt.

* **fix**: don't require pressing esc three times to cancel

# 0.2

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

# 0.0.1

Initial release
