#!/usr/bin/env fish

function message -a msg
    # Native messaging uses a four-byte little-endian byte length prefix.
    set -l x (printf '%08X' (printf '%s' "$msg" | wc -c | string trim))
    printf '%b' "\\x$(string sub -s 7 -l 2 $x)\\x$(string sub -s 5 -l 2 $x)\\x$(string sub -s 3 -l 2 $x)\\x$(string sub -s 1 -l 2 $x)"
    printf '%s' "$msg"
end

function read_scheme -a scheme_path
    test -r $scheme_path || return 1
    jq -c . $scheme_path 2> /dev/null
end

set -q XDG_STATE_HOME && set -l state $XDG_STATE_HOME || set -l state $HOME/.local/state
set -l state_dir $state/caelestia
set -l scheme_path $state_dir/scheme.json

mkdir -p $state_dir

set -l scheme (read_scheme $scheme_path)
if test $status -eq 0 -a -n "$scheme"
    message "$scheme"
end

inotifywait -q -e 'close_write,moved_to,create' -m $state_dir | while read dir events file
    if test "$dir$file" = $scheme_path
        set -l scheme (read_scheme $scheme_path)
        if test $status -eq 0 -a -n "$scheme"
            message "$scheme"
        end
    end
end
