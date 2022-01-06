# zf

zf is a commandline fuzzy finder with a focus on accurate filepath matching

## Building

To provide easier access, zf targets the latest stable version of Zig. Compile
with `zig build`.

## Use

zf accepts lines on stdin and outputs the selection on stdout. Use with a pipe,
or io redirection.

## Why zf over fzf, fzy, selecta, pick, etc?

I created zf to solve a problem I found in all of the fuzzy finders I tried:
none prioritized matches on filenames. Because the filenames in a tree are
typically unique, zf attempts to intelligently alter its matching algorithm to
rank matches on filenames higher.

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

* add commandline arguments
* optimize ranking algorithm
* tidy code
* write neovim telescope sorter extension
* release version 1.0
