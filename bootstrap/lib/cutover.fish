function restore_cli_config --argument-names path backup had_previous
    if test "$bootstrap_dry_run" -eq 1
        return 0
    end
    if test "$had_previous" -eq 1
        if test -z "$backup"; or not test -f "$backup"; or test -L "$backup"
            log "warning: previous CLI config backup is unavailable: $backup"
            return 1
        end
        command mv -f -- "$backup" "$path"; or begin
            log "warning: failed to restore the previous CLI config from $backup"
            return 1
        end
    else if test -e "$path"; or test -L "$path"
        if not test -f "$path"; or test -L "$path"
            log "warning: refusing to remove a non-regular new CLI config at $path"
            return 1
        end
        command unlink -- "$path"; or begin
            log "warning: failed to remove the newly created CLI config at $path"
            return 1
        end
    end
end
