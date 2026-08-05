#!/usr/bin/env fish

set -l active_ws (hyprctl activeworkspace -j | jq -r '.id')
set -l runtime_dir (set -q XDG_RUNTIME_DIR; and echo $XDG_RUNTIME_DIR; or echo /tmp)
set -l state_file "$runtime_dir/caelestia/windowed-workspaces"

if not test -f "$state_file"
    exit
end

if not contains -- "$active_ws" (string split \n -- (cat "$state_file"))
    exit
end

set -l active (hyprctl activewindow -j)
set -l address (printf '%s' "$active" | jq -r '.address // empty')

if test -z "$address"; or test "$address" = "0x0"
    exit
end

set -l window (
    printf '%s' "$active" | jq -r --argjson ws "$active_ws" '
        select(.workspace.id == $ws)
        | select((.mapped // true) == true)
        | select((.hidden // false) == false)
        | [.address, .floating, .at[0], .at[1], .size[0], .size[1]]
        | @tsv
    '
)

if test -z "$window"
    exit
end

set -l win (string split \t -- $window)
set -l batch

if test "$win[2]" != true
    set -a batch "dispatch setfloating address:$win[1]"
    set -a batch "dispatch resizewindowpixel exact $win[5] $win[6],address:$win[1]"
    set -a batch "dispatch movewindowpixel exact $win[3] $win[4],address:$win[1]"
end

set -a batch "dispatch alterzorder top"
hyprctl --batch (string join '; ' $batch)
