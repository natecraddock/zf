# zf

zf is a commandline fuzzy finder that prioritizes matches on filenames.

## Installation

### Arch Linux

An [AUR package](https://aur.archlinux.org/packages/zf/) is available.

### Building from source

zf targets the latest stable release of Zig. Compile with `zig build
-Drelease-fast=true`.

## Use

zf accepts lines on stdin and outputs the selection on stdout. Use with a pipe,
or io redirection.

## Why zf over fzf, fzy, selecta, pick, etc?

I created zf to solve a problem I found in all of the fuzzy finders I tried:
none prioritized matches on filenames.

I [analyzed
filenames](https://nathancraddock.com/blog/in-search-of-a-better-finder/) from
over 50 git repositories and discovered that the majority of filenames are
unique in a given project. I used that knowledge in designing zf's ranking
algorithm to make a fuzzy-finder optimized for filtering filepaths.

* Matches on filenames are prioritized over filepath matches
* Matches on the beginning of a word are prioritized over matches in the middle
  of a word
* Non-sequential character matches are penalized

zf also treats the query string as a sequence of space-separated tokens. This
allows for faster filtering when filenames are not unique.

Imagine searching for an `__init__.py` file in a Python project.

```text
> init
./__init__.py
./ui/__init__.py
./data/__init__.py
./config/__init__.py
```

At this point you can either move the selection down with `c-n` to find
`./config/__init__.py`, or you can add a new token to the query string.

```text
> init c
./config/__init__.py
```

Treating the query string as a sequence of tokens makes filtering more
efficient.

zf will remain simple:
* no full-window interface
* minimal config and options
* sensible defaults

## Does the name 'zf' mean anything?

zf could be interpreted as a shortened [fzf](https://github.com/junegunn/fzf) or
[fzy](https://github.com/jhawthorn/fzy). zf may also be interpreted as "Zig
find" or "Zig fuzzy finder". I like to think of it as a more efficient way to
type `fzf`, emphasizing the speed and precision of the finding algorithm.

## Status

zf now works for fast and accurate file matching. I would like to improve the
tests to prevent regressions and catch corner cases, but it should be usable for
day-to-day fuzzy finding!

### Roadmap

#### 0.3
* improve ranking algorithm
* improve testing
* tidy code
* ship binaries with releases

#### 0.4
* unicode support
