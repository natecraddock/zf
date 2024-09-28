# zf

[![shield showing current tests status](https://github.com/natecraddock/zf/actions/workflows/tests.yml/badge.svg)](https://github.com/natecraddock/zf/actions/workflows/tests.yml) [![Packaging status](https://repology.org/badge/tiny-repos/zf.svg)](https://repology.org/project/zf/versions)

zf is a fuzzy finder that excels at filtering filepaths:

* [because filenames are usually unique](https://nathancraddock.com/blog/in-search-of-a-better-finder/#data-collection), matches on filenames are prioritized
* when the query resembles a file path, zf [uses heuristics for a more accurate match](#strict-path-matching)

The goal of zf is to be more accurate than other fuzzy finders when filtering filepaths, but it also functions as a general-purpose fuzzy finder.

zf is also available as an allocation-free library for fuzzy filtering. [See the docs for more info](https://github.com/natecraddock/zf/blob/main/doc/lib.md).

[Try zf online!](https://nathancraddock.com/zf-playground/)

## Demo

https://user-images.githubusercontent.com/7967463/225198950-a6ab568f-644f-40a1-b202-c12a35aeaed8.mp4

## Features

* fuzzy matching algorithm designed for file paths
* refine search results with whitespace separated query terms
* smartcase (case insensitive unless the query contains uppercase letters)
* multiselect to output multiple selected lines
* preview window
* Zig and C libraries for the zf ranking algorithm

## Docs

* [Usage Documentation](https://github.com/natecraddock/zf/blob/main/doc/zf.md)
* [Library Documentation](https://github.com/natecraddock/zf/blob/main/doc/lib.md)

## Why use zf?

zf was designed knowing that a frequent use case for fuzzy finders is filtering filepaths. It also works great for any arbitrary string, but it is especially good at filtering filepaths with precision.

Specifically,

* Matches on filenames are prioritized over filepath matches
* Matches on the beginning of a word are prioritized over matches in the middle of a word
* Non-sequential character matches are penalized
* Strict path matching offers even more precision

Here are some concrete examples.

### Filename priority

The query is matched first on the filename and then on the path if the filename doesn't match. This example comes from Blender's source code, and was my original inspiration for designing zf.

```text
> make
./GNUmakefile
./source/blender/makesdna/DNA_genfile.h
./source/blender/makesdna/intern/dna_genfile.c
./source/blender/makesrna/intern/rna_cachefile.c
./source/blender/makesdna/DNA_curveprofile_types.h
```

Fzf and fzy both rank `source/blender/makesdna/DNA_genfile.h` first in the results, with `GNUmakefile` 10 items down the list.

### Space-separated tokens

But not every filename is unique. Sometimes there are codebases where there are many files with the same or similar names, like an `__init__.py` in Python, or `.c` and `.h` file pairs in C. In zf each space separated query term is used to narrow down the results. Imagine searching for an `__init__.py` file in a Python project.

```text
> init
./__init__.py
./ui/__init__.py
./data/__init__.py
./config/__init__.py
```

At this point you can either move the selection down with <kdb>Down</kbd> or `c-n` to find
`./config/__init__.py`, or you can add a new token to the query string.

```text
> init c
./config/__init__.py
```

Treating the query string as a sequence of tokens makes filtering more
efficient.

### Strict path matching

This feature is a "do what I mean" feature, more easily used than explained. When the query looks like a path (contains at least one path separator) strict path matching is enabled.

Path segments are the portions of a path delimited by path separators. `foo/bar` has segments `foo` and `bar`. With strict path matching the path segments of the query token must not span across path segments in the candidate. As an example, the query `foo/` would match `foo/bar/` but not `fo/obar/` because the characters `"foo"` must appear in a single path segment.

This is useful for narrowing down results when you know the exact path structure of your files. With the following paths

```
./app/models/foo/bar/baz.rb
./app/models/foo/bar-baz.rb
./app/models/foo-bar-baz.rb
./app/monsters/dungeon/foo/bar/baz.rb
```

Strict path matching ensures that the intended path structure is found.

```
> a/m/f/b/baz
./app/models/foo/bar/baz.rb
```

In other fuzzy finders the string `app/monsters/dungeon/foo/bar/baz.rb` is also included in the results. Strict path matching prevents this because there is a slash between `onsters/dungeon` and nothing in the query matches the `dungeon` segment.

To end strict path matching, just add a space to start a new query token.

## Installation

### Arch Linux

An [AUR package](https://aur.archlinux.org/packages/zf/) is available.

### macOS

Install with Homebrew

```
brew install zf
```

### Nix

```
nix-env --install zf
```

### Binaries

Each [release](https://github.com/natecraddock/zf/releases/latest) has binaries attached for macOS and Linux.

### Building from source

For compatibility with system package managers, zf targets the latest stable release of Zig.

```
git clone https://github.com/natecraddock/zf
cd zf
zig build -Doptimize=ReleaseSafe --summary all
```

The executable will be created in `./zig-out/bin/zf`. For debug builds omit `-Doptimize=ReleaseSafe`.

## Integrations

Would you like to use zf in an editor? Try one of the following plugins

* [zf.vim](https://github.com/ratfactor/zf.vim): zf integrated with vim for
  fuzzy file finding. Similar to fzf.vim.
* [telescope-zf-native.nvim](https://github.com/natecraddock/telescope-zf-native.nvim)
  a neovim [telescope](https://github.com/nvim-telescope/telescope.nvim)
  extension to override the default Lua sorter with zf.

## Contributing

I am open to contributions of all kinds, but be aware that I want to keep zf small and easy to maintain.
