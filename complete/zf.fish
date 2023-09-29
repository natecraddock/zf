complete -c zf -f

complete -f -c zf -s d -l delimiter -d "Set the delimiter used to split candidates (default \n)"
complete -f -c zf -s 0 -d "Shorthand for -d'\0' to split on null bytes"
complete -f -c zf -s f -l filter -d "Skip interactive use and filter using the given query"
complete -f -c zf -l height -d "The height of the interface in rows (default 10)"
complete -f -c zf -s k -l keep-order -d "Don't sort by rank and preserve order of lines read on stdin"
complete -x -c zf -s l -l lines -d "Alias of --height (deprecated)"
complete -f -c zf -s p -l plain -d "Treat input as plaintext and disable filepath matching features"
complete -f -c zf -s v -l version -d "Show version information and exit"
complete -f -c zf -s h -l help -d "Display this help and exit"
