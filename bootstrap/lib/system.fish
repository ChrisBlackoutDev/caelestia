function bootstrap_pacman
    command /usr/bin/pacman $argv
end

function package_version --argument-names package
    set -l query (bootstrap_pacman -Q -- "$package" 2>/dev/null)
    if test $status -ne 0
        return 1
    end
    string split ' ' -f 2 -- "$query"
end

function validate_same_installed_version --argument-names label
    set -l packages $argv[2..-1]
    set -l reference_version
    set -l installed

    for package in $packages
        set -l value (package_version "$package")
        if test $status -ne 0; or test -z "$value"
            echo "error: $label validation requires installed package '$package'" >&2
            return 1
        end
        set -a installed "$package=$value"
        if test -z "$reference_version"
            set reference_version "$value"
        else if test "$value" != "$reference_version"
            echo "error: $label version mismatch: "(string join ', ' $installed) >&2
            return 1
        end
    end
end

function validate_fully_updated
    if test "$bootstrap_dry_run" -eq 1
        log "would require pacman -Qu to report no pending official upgrades"
        return 0
    end

    set -l query_errors (mktemp)
    if test $status -ne 0
        echo "error: could not create temporary storage for the pacman query" >&2
        return 1
    end
    set -l pending (bootstrap_pacman -Qu 2>"$query_errors")
    set -l query_status $status
    set -l query_error_output (string collect <"$query_errors")
    command rm -f -- "$query_errors"
    if test $query_status -ne 0; and test $query_status -ne 1
        echo "error: pacman could not determine whether official upgrades are pending" >&2
        return 1
    end
    if test $query_status -eq 1; and test -n "$query_error_output"
        echo "error: pacman could not determine whether official upgrades are pending" >&2
        printf '  %s\n' "$query_error_output" >&2
        return 1
    end
    if test (count $pending) -gt 0
        echo "error: pending official upgrades detected; perform the separately gated full Arch upgrade and reboot first" >&2
        printf '  %s\n' $pending >&2
        return 1
    end

    validate_same_installed_version NetworkManager/libnm networkmanager libnm; or return 1
    validate_same_installed_version "GCC runtime" gcc gcc-libs libgcc libstdc++ lib32-gcc-libs; or return 1
end
