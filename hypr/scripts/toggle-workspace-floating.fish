#!/usr/bin/env fish

set -l active_ws (hyprctl activeworkspace -j | jq -r '.id')
set -l clients (hyprctl clients -j)
set -l runtime_dir (set -q XDG_RUNTIME_DIR; and echo $XDG_RUNTIME_DIR; or echo /tmp)
set -l state_dir "$runtime_dir/caelestia"
set -l state_file "$state_dir/windowed-workspaces"
set -l state_ws

if test -f "$state_file"
    set state_ws (string split \n -- (cat "$state_file"))
end

set -l tiled_count (
    printf '%s' "$clients" | jq -r --argjson ws "$active_ws" '
        [
            .[]
            | select(.workspace.id == $ws)
            | select((.mapped // true) == true)
            | select((.hidden // false) == false)
            | select(.floating == false)
        ]
        | length
    '
)

set -l dispatcher
set -l message

if contains -- "$active_ws" $state_ws
    set dispatcher settiled
    set message 'Workspace windows tiled'
else if test "$tiled_count" -gt 0
    set dispatcher setfloating
    set message 'Workspace windows floating'
else
    set dispatcher settiled
    set message 'Workspace windows tiled'
end

if test "$dispatcher" = settiled
    set windows (
        printf '%s' "$clients" | jq -r --argjson ws "$active_ws" '
            [
                .[]
                | select(.workspace.id == $ws)
                | select((.mapped // true) == true)
                | select((.hidden // false) == false)
            ]
            | sort_by(-(.at[0] + (.size[0] / 2)), -(.at[1] + (.size[1] / 2)))
            | .[]
            | [.address, .at[0], .at[1], .size[0], .size[1]]
            | @tsv
        '
    )
else
    set windows (
        printf '%s' "$clients" | jq -r --argjson ws "$active_ws" '
            .[]
            | select(.workspace.id == $ws)
            | select((.mapped // true) == true)
            | select((.hidden // false) == false)
            | [.address, .at[0], .at[1], .size[0], .size[1]]
            | @tsv
        '
    )
end

if test (count $windows) -eq 0
    notify-send -u low -i view-grid-symbolic -a Shell 'Window layout' 'No windows on this workspace'
    exit
end

set -l batch
for window in $windows
    set -l win (string split \t -- $window)
    set -l address $win[1]

    set -a batch "dispatch $dispatcher address:$address"

    if test "$dispatcher" = setfloating
        set -l x $win[2]
        set -l y $win[3]
        set -l width $win[4]
        set -l height $win[5]

        set -a batch "dispatch resizewindowpixel exact $width $height,address:$address"
        set -a batch "dispatch movewindowpixel exact $x $y,address:$address"
    end
end

hyprctl --batch (string join '; ' $batch)

set -l next_state
for ws in $state_ws
    if test -n "$ws"; and test "$ws" != "$active_ws"
        set -a next_state "$ws"
    end
end

if test "$dispatcher" = setfloating
    mkdir -p "$state_dir"
    set -a next_state "$active_ws"
end

if test (count $next_state) -gt 0
    printf '%s\n' $next_state > "$state_file"
else
    rm -f "$state_file"
end

notify-send -u low -i view-grid-symbolic -a Shell 'Window layout' "$message"
