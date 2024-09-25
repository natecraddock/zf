# zf - a commandline fuzzy finder that prioritizes matches on filenames

## SYNOPSIS
`zf [options]`

## DESCRIPTION
zf is a simple, general-purpose fuzzy finder that prioritizes matches on filenames.

zf reads a list of newline separated strings on stdin and displays an interactive interface. Pressing enter outputs the selected line on stdout. Text may be entered to filter the list of strings.

Multiple lines may be marked as selected with `tab` and `shift-tab`. When multiple lines are selected, pressing enter outputs only the marked lines to stdout.

Each whitespace-separated term in the query string is used separately to narrow down the search results. For example, searching for "init config" will select all results that match both "init" and "config". Note that the query is restricted to a maximum of 16 whitespace-separated tokens.

Matching is case insensitive unless an uppercase letter is found in the query.

## OPTIONS

`-d, --delimiter`: Set the delimiter used to split candidates (default \n)

`-0`: Shorthand for `-d'\0'` to split on null bytes

`-f, --filter`: Skip interactive use and filter using the given query

`--height`: The height of the interface in rows (default 10)

`-k, --keep-order`: Don't sort by rank and preserve order of lines read on stdin. This makes zf remove any lines that don't match, but the order of lines will not change.

`-l, --lines`: Alias of `--height`. Deprecated and will be removed in version 1.0.0.

`-p, --plain`: Treat input as plaintext and disable filepath matching features. Useful when the input lines are not file paths.

`--preview`: Executes a command substituting {} with the current selected line and displays the output in a side column.

`--preview-width`: Sets the preview column width (default 60%).

`-v, --version`: Show version information and exit

`-h, --help`: Display help and exit

## ENV VARIABLES

`ZF_PROMPT`: Override the default `> ` prompt by assigning a string to this variable. For example `export ZF_PROMPT="$ "`.

`ZF_HIGHLIGHT`: Set the color used to highlight matches. Valid colors are: black, red, green, yellow, blue, magenta, cyan, white, bright_black, bright_red, bright_green, bright_yellow, bright_blue, bright_magenta, bright_cyan, and bright_white. The default color is cyan.

`ZF_VI_MODE`: When this variable is present and not empty `ctrl+k` moves up a line. When disabled `ctrl+k` deletes from the cursor to the end of line.

`NO_COLOR`: Disables colors. See https://no-color.org.

## COMMANDS

`enter`: Write the selected line or all marked lines to stdout and exit

`escape, ctrl-c`: Exit zf without selecting anything

`up, ctrl-p, ctrl-k`: Select the next line up (`ctrl-k` only when `ZF_VI_MODE` is enabled)

`down ctrl-n, ctrl-j`: Select the next line down

`tab`: Mark the current line as selected and select the next line

`shift-tab`: Mark the current line as selected and select the previous line

`left, ctrl-b`: Move the cursor left

`right, ctrl-f`: Move the cursor right

`ctrl-a`: Move the cursor to the beginning of the line

`ctrl-e`: Move the cursor to the end of the line

`backspace, ctrl-h`: Delete the character before the cursor

`delete, ctrl-d`: Delete the character under the cursor

`ctrl-w`: Delete the word before the cursor

`ctrl-u`: Delete from the cursor to the beginning of the line

`ctrl-k`: Delete from the cursor to the end of line when `ZF_VI_MODE` is disabled

## EXAMPLES

`find -type f | zf` : Fuzzy find on the file tree in the current directory

`vim $(find -type f | zf)` : Fuzzy find on the file tree and open the selcted file in vim

`git switch $(git branch | cut -c 3- | zf)` : Switch to selected git branch

`find -type f | zf --preview 'cat {}'`: Fuzzy find files and show a preview of the contents using cat

## EXIT STATUS

`0` : Success

`1` : No candidates given on stdin or aborted the interactive interface with esc or ctrl-c

`2` : Error
