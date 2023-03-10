complete -c zf -f

complete -f -c zf -s f -l filter -d "Skip interactive use and filter using the given query"
complete -f -c zf -s k -l keep-order -d "Don't sort by rank and preserve order of lines read on stdin"
complete -x -c zf -s l -l lines -d "Set the maximum number of result lines to show (default 10)"
complete -f -c zf -s p -l plain -d "Treat input as plaintext and disable filepath matching features"
complete -f -c zf -s v -l version -d "Show version information and exit"
complete -f -c zf -s h -l help -d "Display this help and exit"
