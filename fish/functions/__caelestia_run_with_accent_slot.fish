function __caelestia_restore_terminal_palette
    cat ~/.local/state/caelestia/sequences.txt 2>/dev/null
end

function __caelestia_set_terminal_accent_slot
    set -l slot $argv[1]
    set -l scheme ~/.local/state/caelestia/scheme.json
    set -l accent

    if test -r $scheme; and command -q jq
        set accent (jq -r '.colours.primary // .colours.surfaceTint // empty' $scheme 2> /dev/null)
    end

    if not string match -rq '^[0-9A-Fa-f]{6}$' -- "$accent"
        return 1
    end

    set -l red (string sub -s 1 -l 2 -- $accent)
    set -l green (string sub -s 3 -l 2 -- $accent)
    set -l blue (string sub -s 5 -l 2 -- $accent)

    printf '\e]4;%s;rgb:%s/%s/%s\e\\' $slot $red $green $blue
end

function __caelestia_run_with_accent_slot
    set -l slot $argv[1]
    set -e argv[1]

    __caelestia_set_terminal_accent_slot $slot
    command $argv
    set -l command_status $status
    __caelestia_restore_terminal_palette

    return $command_status
end
