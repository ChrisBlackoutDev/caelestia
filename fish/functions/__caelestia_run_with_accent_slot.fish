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

function __caelestia_scheme_colour
    set -l name $argv[1]
    set -l fallback $argv[2]
    set -l scheme ~/.local/state/caelestia/scheme.json
    set -l colour

    if test -r $scheme; and command -q jq
        set colour (jq -r --arg name $name '.colours[$name] // empty' $scheme 2>/dev/null)
    end

    if string match -rq '^[0-9A-Fa-f]{6}$' -- "$colour"
        echo $colour
    else
        echo $fallback
    end
end

function __caelestia_set_terminal_palette_slot
    set -l slot $argv[1]
    set -l colour $argv[2]

    if not string match -rq '^[0-9A-Fa-f]{6}$' -- "$colour"
        return 1
    end

    set -l red (string sub -s 1 -l 2 -- $colour)
    set -l green (string sub -s 3 -l 2 -- $colour)
    set -l blue (string sub -s 5 -l 2 -- $colour)

    printf '\e]4;%s;rgb:%s/%s/%s\e\\' $slot $red $green $blue
end

function __caelestia_set_terminal_rainbow_slots
    __caelestia_set_terminal_palette_slot 1 (__caelestia_scheme_colour red ff9888)
    __caelestia_set_terminal_palette_slot 2 (__caelestia_scheme_colour primary f9b7a5)
    __caelestia_set_terminal_palette_slot 3 (__caelestia_scheme_colour tertiary ffe1b2)
    __caelestia_set_terminal_palette_slot 4 (__caelestia_scheme_colour blue ffa2bd)
    __caelestia_set_terminal_palette_slot 5 (__caelestia_scheme_colour mauve ffa9ab)
    __caelestia_set_terminal_palette_slot 6 (__caelestia_scheme_colour teal ffdb94)
    __caelestia_set_terminal_palette_slot 7 (__caelestia_scheme_colour text f9e0da)
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

function __caelestia_run_with_rainbow_slots
    __caelestia_set_terminal_rainbow_slots
    command $argv
    set -l command_status $status
    __caelestia_restore_terminal_palette

    return $command_status
end
