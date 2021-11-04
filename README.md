# zf

zf is a commandline fuzzy finder with a special focus on filepath finding

## Why zf over fzf, fzy, selecta, pick, etc?

I created zf to solve one problem I found in all alternatives I tried: no widely
available fuzzy finder makes a special emphasis on filename matching. zf
attempts to intelligently alter its matching algorithm to prioritize matches on
the names of files.

## Does the name 'zf' mean anything?

zf could be interpreted as a shortened [fzf](https://github.com/junegunn/fzf) or
[fzy](https://github.com/jhawthorn/fzy). zf may also be interpreted as "Zig
find" or "Zig fuzzy finder". I like to think of it as a more efficient way to
type `fzf`, emphasizing the speed and precision of the finding algorithm.

## Status

zf now works as an alternative to popular fuzzy finders. The fuzzy algorithm is
*far too fuzzy* at the moment, but now that the basic framework is laid out that
improving matching is the next focus.
