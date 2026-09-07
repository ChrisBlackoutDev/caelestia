set -g migrated_legacy_paths
set -g migrated_legacy_journal

function legacy_origin_allowed --argument-names origin
    contains -- "$origin" \
        https://github.com/ChrisBlackoutDev/caelestia.git \
        git@github.com:ChrisBlackoutDev/caelestia.git \
        ssh://git@github.com/ChrisBlackoutDev/caelestia.git
end

function validate_legacy_journal --argument-names journal
    if not string match -q -- '/*' "$journal"; or test "$journal" = "$HOME"
        echo "error: legacy-link journal must be an absolute child path of HOME" >&2
        return 1
    end

    set -l journal_parent (realpath (dirname "$journal") 2>/dev/null)
    set -l home_real (realpath "$HOME")
    if test -z "$journal_parent"; or begin
            test "$journal_parent" != "$home_real"; and not string match -q -- "$home_real/*" "$journal_parent"
        end
        echo "error: legacy-link journal parent must already exist beneath HOME: "(dirname "$journal") >&2
        return 1
    end

    if test "$bootstrap_dry_run" -eq 1
        return 0
    end
    if not test -d "$journal"; or test -L "$journal"
        echo "error: legacy-link journal must be a pre-created, non-symlink directory: $journal" >&2
        return 1
    end
    if test (stat -c %u "$journal") -ne (id -u)
        echo "error: legacy-link journal is not owned by the target user: $journal" >&2
        return 1
    end
    set -l completed "$journal/COMPLETED"
    if test -e "$completed"; or test -L "$completed"
        echo "error: legacy-link journal records a completed cutover and must not be reused: $completed" >&2
        return 1
    end
end

function mark_legacy_journal_complete --argument-names journal
    if test "$bootstrap_dry_run" -eq 1
        log "would mark the legacy-link journal completed after replacement validation"
        return 0
    end

    set -l completed "$journal/COMPLETED"
    if test -e "$completed"; or test -L "$completed"
        echo "error: refusing to overwrite a legacy-link completion marker: $completed" >&2
        return 1
    end
    set -l temporary (mktemp "$journal/.COMPLETED.XXXXXX"); or return 1
    printf 'completed_at=%s\nhost=%s\nuser=%s\n' (date -u +%Y-%m-%dT%H:%M:%SZ) (uname -n) (id -un) >"$temporary"; or begin
        command rm -f -- "$temporary"
        return 1
    end
    command mv -- "$temporary" "$completed"; or begin
        command rm -f -- "$temporary"
        return 1
    end
end

function clear_legacy_completion_marker --argument-names journal
    if test -z "$journal"; or test "$bootstrap_dry_run" -eq 1
        return 0
    end
    set -l completed "$journal/COMPLETED"
    if not test -e "$completed"; and not test -L "$completed"
        return 0
    end
    if not test -f "$completed"; or test -L "$completed"
        log "warning: refusing to remove an unsafe legacy-link completion marker: $completed"
        return 1
    end
    command rm -f -- "$completed"
end

function legacy_link_pairs
    set -l legacy "$HOME/.local/share/caelestia"
    set -l config_home (set -q XDG_CONFIG_HOME; and echo "$XDG_CONFIG_HOME"; or echo "$HOME/.config")
    set -l data_home (set -q XDG_DATA_HOME; and echo "$XDG_DATA_HOME"; or echo "$HOME/.local/share")
    printf '%s\t%s\n' \
        "$config_home/btop" "$legacy/btop" \
        "$config_home/fastfetch" "$legacy/fastfetch" \
        "$config_home/fish" "$legacy/fish" \
        "$config_home/foot" "$legacy/foot" \
        "$config_home/hypr" "$legacy/hypr" \
        "$config_home/starship.toml" "$legacy/starship.toml" \
        "$config_home/uwsm" "$legacy/uwsm" \
        "$config_home/caelestia/shell.json" "$legacy/caelestia/shell.json" \
        "$data_home/applications/OrcaSlicer.desktop" "$legacy/applications/OrcaSlicer.desktop" \
        "$data_home/applications/cursor.desktop" "$legacy/applications/cursor.desktop" \
        "$data_home/applications/steam.desktop" "$legacy/applications/steam.desktop"
end

function legacy_link_is_exact --argument-names path expected
    test -L "$path"; or return 1
    test (readlink -- "$path") = "$expected"; or return 1
    test (realpath -- "$path" 2>/dev/null) = "$expected"
end

function write_legacy_journal_manifest --argument-names journal
    if test "$bootstrap_dry_run" -eq 1
        return 0
    end

    set -l manifest "$journal/expected.tsv"
    set -l temporary (mktemp "$journal/.expected.tsv.XXXXXX"); or return 1
    for pair in (legacy_link_pairs)
        set -l fields (string split \t -- "$pair")
        set -l relative (string replace -- "$HOME/" '' "$fields[1]")
        printf '%s\t%s\n' "$relative" "$fields[2]" >>"$temporary"; or begin
            command rm -f -- "$temporary"
            return 1
        end
    end

    if test -e "$manifest"; or test -L "$manifest"
        if not test -f "$manifest"; or test -L "$manifest"; or not command cmp -s -- "$temporary" "$manifest"
            command rm -f -- "$temporary"
            echo "error: legacy-link journal manifest does not match this bootstrap: $manifest" >&2
            return 1
        end
        command rm -f -- "$temporary"
    else
        command mv -- "$temporary" "$manifest"; or begin
            command rm -f -- "$temporary"
            return 1
        end
    end
end

function legacy_recovery_root --argument-names journal
    set -l base "$journal/failed-replacements-"(date -u +%Y%m%dT%H%M%SZ)"-$fish_pid"
    set -l candidate "$base"
    set -l suffix 0
    while test -e "$candidate"; or test -L "$candidate"
        set suffix (math $suffix + 1)
        set candidate "$base-$suffix"
    end
    printf '%s\n' "$candidate"
end

function restore_migrated_legacy_links
    if test (count $migrated_legacy_paths) -eq 0
        return 0
    end

    set -l restore_status 0
    set -l recovery_root
    for path in $migrated_legacy_paths[-1..1]
        set -l relative (string replace -- "$HOME/" '' "$path")
        set -l saved "$migrated_legacy_journal/$relative"

        if not test -e "$saved"; and not test -L "$saved"
            # A prior rollback may already have restored this exact link.
            set -l expected
            for pair in (legacy_link_pairs)
                set -l fields (string split \t -- "$pair")
                if test "$fields[1]" = "$path"
                    set expected "$fields[2]"
                    break
                end
            end
            if test -n "$expected"; and legacy_link_is_exact "$path" "$expected"
                continue
            end
            log "warning: saved legacy link is missing from the journal: $saved"
            set restore_status 1
            continue
        end

        if test -e "$path"; or test -L "$path"
            if test -z "$recovery_root"
                set recovery_root (legacy_recovery_root "$migrated_legacy_journal")
            end
            set -l recovered "$recovery_root/$relative"
            mkdir -p (dirname "$recovered"); or begin
                set restore_status 1
                continue
            end
            command mv -- "$path" "$recovered"; or begin
                log "warning: failed to preserve a partial managed replacement: $path"
                set restore_status 1
                continue
            end
            log "preserved partial managed replacement at $recovered"
        end

        mkdir -p (dirname "$path"); or begin
            set restore_status 1
            continue
        end
        command mv -- "$saved" "$path"; or set restore_status 1
    end

    if test $restore_status -eq 0
        set -g migrated_legacy_paths
    end
    return $restore_status
end

function validate_migrated_replacements
    for path in $migrated_legacy_paths
        if not test -e "$path"; or test -L "$path"
            echo "error: managed config did not replace the migrated legacy link with a real path: $path" >&2
            return 1
        end
    end
end

function migrate_allowlisted_legacy_links --argument-names journal
    set -l legacy "$HOME/.local/share/caelestia"
    if not test -d "$legacy/.git"
        log "legacy checkout is absent; no legacy links to migrate"
        return 0
    end

    set -l origin (git -C "$legacy" remote get-url origin 2>/dev/null)
    if not legacy_origin_allowed "$origin"
        echo "error: refusing legacy-link migration for unrecognized origin '$origin'" >&2
        return 1
    end

    validate_legacy_journal "$journal"; or return 1
    set -l pairs (legacy_link_pairs)

    # Validate every observed path and journal destination before moving anything.
    for pair in $pairs
        set -l fields (string split \t -- "$pair")
        set -l path $fields[1]
        set -l expected $fields[2]
        set -l relative (string replace -- "$HOME/" '' "$path")
        set -l saved "$journal/$relative"
        set -l live_exists 0
        set -l saved_exists 0
        if test -e "$path"; or test -L "$path"
            set live_exists 1
        end
        if test -e "$saved"; or test -L "$saved"
            set saved_exists 1
        end

        if test $saved_exists -eq 1
            if not legacy_link_is_exact "$saved" "$expected"
                echo "error: saved legacy link does not match the exact expected target: $saved" >&2
                return 1
            end
            if test $live_exists -eq 1; and test -L "$path"
                echo "error: a saved legacy link and a live symlink both exist for: $path" >&2
                return 1
            end
        else if test $live_exists -eq 1; and not legacy_link_is_exact "$path" "$expected"
            set -l link_target (readlink -- "$path" 2>/dev/null)
            echo "error: legacy link does not match the exact expected target: $path -> $link_target" >&2
            return 1
        end
    end

    write_legacy_journal_manifest "$journal"; or return 1
    set -g migrated_legacy_paths
    set -g migrated_legacy_journal "$journal"

    for pair in $pairs
        set -l fields (string split \t -- "$pair")
        set -l path $fields[1]
        set -l expected $fields[2]
        set -l relative (string replace -- "$HOME/" '' "$path")
        set -l saved "$journal/$relative"

        if test -e "$saved"; or test -L "$saved"
            set -a migrated_legacy_paths "$path"
            continue
        end
        if not test -L "$path"
            continue
        end
        if test "$bootstrap_dry_run" -eq 1
            printf '[dry-run] mv %s %s  # -> %s\n' (string escape -- "$path") (string escape -- "$saved") (string escape -- "$expected")
            continue
        end

        # Track before the first mutation so a signal between mv and the next
        # Fish statement still restores (or recognizes) this exact path.
        set -a migrated_legacy_paths "$path"
        mkdir -p (dirname "$saved"); or begin
            restore_migrated_legacy_links
            return 1
        end
        command mv -- "$path" "$saved"; or begin
            restore_migrated_legacy_links
            return 1
        end
    end
end
