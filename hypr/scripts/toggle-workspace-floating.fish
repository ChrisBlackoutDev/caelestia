#!/usr/bin/env fish

set -l active_ws (hyprctl activeworkspace -j | jq -r '.id')
set -l clients (hyprctl clients -j)

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

if test "$tiled_count" -gt 0
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
notify-send -u low -i view-grid-symbolic -a Shell 'Window layout' "$message"
