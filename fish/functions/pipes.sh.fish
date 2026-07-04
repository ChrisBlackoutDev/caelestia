function pipes.sh --wraps pipes.sh --description 'Run pipes.sh with Caelestia terminal colours and restore the palette on exit'
    source ~/.config/fish/functions/__caelestia_run_with_accent_slot.fish

    if contains -- -h $argv; or contains -- -v $argv
        command pipes.sh $argv
        return $status
    end

    __caelestia_run_with_rainbow_slots pipes.sh -c 1 -c 2 -c 3 -c 4 -c 5 -c 6 -c 7 $argv
end
