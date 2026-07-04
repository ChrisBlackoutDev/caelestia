function cava --wraps cava --description 'Run cava with a Caelestia-generated gradient'
    set -l config_path (python3 ~/.config/fish/scripts/caelestia-cava-config.py)

    if test -n "$config_path"; and test -r "$config_path"
        command cava -p "$config_path" $argv
        set -l command_status $status
        rm -f "$config_path"
        return $command_status
    end

    command cava $argv
end
