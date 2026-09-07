#!/usr/bin/env fish

set -l root (realpath (status dirname)/..)
source "$root/bootstrap/lib/profile.fish"
source "$root/bootstrap/lib/legacy.fish"
source "$root/bootstrap/lib/cutover.fish"

set -l profile kensa-desktop
set -l stage
set -l helper_override
set -l noconfirm 0
set -l dry_run 0
set -l approve_aur 0
set -l migrate_legacy_links 0
set -l legacy_link_journal
set -l sync_profile_components 0
set -l package_groups
set -l enabled_services
set -l approved_groups

function usage
    echo "usage: bootstrap/install.fish --stage core|profile [--profile NAME] [--aur-helper yay|paru] [--dry-run]"
    echo "                              [--approve-aur] [--noconfirm]"
    echo "       core migration:        [--migrate-legacy-links --legacy-link-journal ABSOLUTE_PATH]"
    echo "       profile package batch: --package-group official.NAME|aur.NAME"
    echo "       profile component sync: --sync-profile-components --approve-aur"
    echo "       explicit finishing:     --enable-service SERVICE | --approve-group GROUP"
end

set -l i 1
while test $i -le (count $argv)
    set -l arg $argv[$i]
    switch $arg
        case '--profile=*'
            set profile (string replace -- '--profile=' '' $arg)
        case --profile
            set i (math $i + 1)
            if test $i -gt (count $argv)
                echo "error: --profile requires a value" >&2
                exit 2
            end
            set profile $argv[$i]
        case '--stage=*'
            set stage (string replace -- '--stage=' '' $arg)
        case --stage
            set i (math $i + 1)
            if test $i -gt (count $argv)
                echo "error: --stage requires a value" >&2
                exit 2
            end
            set stage $argv[$i]
        case '--aur-helper=*'
            set helper_override (string replace -- '--aur-helper=' '' $arg)
        case --aur-helper
            set i (math $i + 1)
            if test $i -gt (count $argv)
                echo "error: --aur-helper requires a value" >&2
                exit 2
            end
            set helper_override $argv[$i]
        case --noconfirm
            set noconfirm 1
        case --dry-run
            set dry_run 1
        case --approve-aur
            set approve_aur 1
        case --migrate-legacy-links
            set migrate_legacy_links 1
        case '--legacy-link-journal=*'
            set legacy_link_journal (string replace -- '--legacy-link-journal=' '' $arg)
        case --legacy-link-journal
            set i (math $i + 1)
            if test $i -gt (count $argv)
                echo "error: --legacy-link-journal requires a value" >&2
                exit 2
            end
            set legacy_link_journal $argv[$i]
        case --sync-profile-components
            set sync_profile_components 1
        case '--package-group=*'
            set -a package_groups (string replace -- '--package-group=' '' $arg)
        case --package-group
            set i (math $i + 1)
            if test $i -gt (count $argv)
                echo "error: --package-group requires a value" >&2
                exit 2
            end
            set -a package_groups $argv[$i]
        case '--enable-service=*'
            set -a enabled_services (string replace -- '--enable-service=' '' $arg)
        case --enable-service
            set i (math $i + 1)
            if test $i -gt (count $argv)
                echo "error: --enable-service requires a value" >&2
                exit 2
            end
            set -a enabled_services $argv[$i]
        case '--approve-group=*'
            set -a approved_groups (string replace -- '--approve-group=' '' $arg)
        case --approve-group
            set i (math $i + 1)
            if test $i -gt (count $argv)
                echo "error: --approve-group requires a value" >&2
                exit 2
            end
            set -a approved_groups $argv[$i]
        case -h --help
            usage
            exit 0
        case '*'
            echo "error: unknown option '$arg'" >&2
            usage >&2
            exit 2
    end
    set i (math $i + 1)
end

if not contains -- "$stage" core profile
    echo "error: an explicit --stage core or --stage profile is required" >&2
    exit 2
end

if test -n "$helper_override"; and not contains -- "$helper_override" yay paru
    echo "error: --aur-helper must be yay or paru" >&2
    exit 2
end

if test "$noconfirm" -eq 1; and test "$dry_run" -eq 0
    echo "error: --noconfirm is accepted only with --dry-run; live package transactions must remain interactive" >&2
    exit 2
end

if test "$stage" = core
    if test (count $package_groups) -gt 0; or test $sync_profile_components -eq 1
        echo "error: --package-group and --sync-profile-components apply only to the profile stage" >&2
        exit 2
    end
    if test (count $enabled_services) -gt 0; or test (count $approved_groups) -gt 0
        echo "error: service and group changes are not allowed in the core stage" >&2
        exit 2
    end
else
    if test $migrate_legacy_links -eq 1; or test -n "$legacy_link_journal"
        echo "error: legacy-link migration is allowed only in the core stage" >&2
        exit 2
    end
    if test (count $package_groups) -gt 1
        echo "error: run exactly one --package-group per profile package transaction" >&2
        exit 2
    end
    if test (count $enabled_services) -gt 1
        echo "error: run exactly one --enable-service per service transaction" >&2
        exit 2
    end
    if test (count $approved_groups) -gt 1
        echo "error: run exactly one --approve-group per group transaction" >&2
        exit 2
    end
    set -l transaction_count (math (count $package_groups) + $sync_profile_components + (count $enabled_services) + (count $approved_groups))
    if test $transaction_count -ne 1
        echo "error: profile stage requires exactly one package, component-sync, service, or group transaction" >&2
        exit 2
    end
end

if test $migrate_legacy_links -eq 1; and test -z "$legacy_link_journal"
    echo "error: --migrate-legacy-links requires --legacy-link-journal ABSOLUTE_PATH" >&2
    exit 2
end
if test $migrate_legacy_links -eq 0; and test -n "$legacy_link_journal"
    echo "error: --legacy-link-journal requires --migrate-legacy-links" >&2
    exit 2
end

set -l profile_file (profile_path $profile)
if test $status -ne 0
    echo "error: profile '$profile' not found under $root/profiles" >&2
    exit 1
end

set -g bootstrap_dry_run $dry_run
set -g bootstrap_noconfirm $noconfirm

function log
    printf '[bootstrap] %s\n' "$argv"
end

function log_list --argument-names label
    set -l values $argv[2..-1]
    if test (count $values) -eq 0
        log "$label (0): none"
    else
        log "$label ("(count $values)"): "(string join ', ' $values)
    end
end

function print_command --argument-names prefix
    printf '%s %s\n' "$prefix" (string join -- ' ' (string escape -- $argv[2..-1]))
end

function run
    if test "$bootstrap_dry_run" -eq 1
        print_command '[dry-run]' $argv
    else
        command $argv
    end
end

function sudo_run
    if test "$bootstrap_dry_run" -eq 1
        print_command '[dry-run] sudo' $argv
    else
        command sudo $argv
    end
end

function sudo_run_inhibited
    if test "$bootstrap_dry_run" -eq 1
        print_command '[dry-run] sudo systemd-inhibit --what=idle:sleep:shutdown --why=Caelestia\ profile\ package\ transaction' $argv
    else if command -q systemd-inhibit
        command sudo systemd-inhibit \
            --what=idle:sleep:shutdown \
            --why="Caelestia profile package transaction" \
            $argv
    else
        command sudo $argv
    end
end

function run_inhibited
    if test "$bootstrap_dry_run" -eq 1
        print_command '[dry-run] systemd-inhibit --what=idle --why=Caelestia\ component\ installation' $argv
    else if command -q systemd-inhibit
        command systemd-inhibit --what=idle --why="Caelestia component installation" $argv
    else
        command $argv
    end
end

function unique_values
    printf '%s\n' $argv | string match -rv '^$' | sort -u
end

function package_version --argument-names package
    set -l query (pacman -Q -- "$package" 2>/dev/null)
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

    set -l pending (pacman -Qu 2>/dev/null)
    set -l query_status $status
    if test $query_status -ne 0
        echo "error: pacman could not determine whether official upgrades are pending" >&2
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

function require_tty
    if test "$bootstrap_dry_run" -eq 1
        return 0
    end
    if not test -t 0
        echo "error: a live install requires a TTY because package helpers and caelestia-cli may invoke sudo" >&2
        echo "rerun through ssh -tt or from a local text console" >&2
        return 1
    end
end

function aur_helper_build_dep --argument-names helper
    switch "$helper"
        case yay
            echo go
        case paru
            echo cargo
    end
end

function install_aur_helper --argument-names helper
    if command -q "$helper"
        return 0
    end
    if test "$bootstrap_dry_run" -eq 0; and test $approve_aur -ne 1
        echo "error: --approve-aur is required before building an AUR helper" >&2
        return 1
    end

    log "installing reviewed AUR helper: $helper"
    set -l dependency (aur_helper_build_dep "$helper")
    sudo_run_inhibited pacman -S --needed base-devel git $dependency; or return 1

    set -l cache_home (set -q XDG_CACHE_HOME; and echo "$XDG_CACHE_HOME"; or echo "$HOME/.cache")
    set -l helper_dir "$cache_home/caelestia-bootstrap/aur/$helper"
    if test "$bootstrap_dry_run" -eq 1
        log "would clone https://aur.archlinux.org/$helper.git into $helper_dir, show its PKGBUILD, then build it"
        return 0
    end

    mkdir -p (dirname "$helper_dir"); or return 1
    if test -d "$helper_dir/.git"
        git -C "$helper_dir" fetch origin master; or return 1
        git -C "$helper_dir" merge --ff-only origin/master; or return 1
    else
        git clone "https://aur.archlinux.org/$helper.git" "$helper_dir"; or return 1
    end
    command cat "$helper_dir/PKGBUILD"; or return 1

    set -l previous_dir (pwd)
    cd "$helper_dir"; or return 1
    makepkg --syncdeps --install --needed
    set -l build_status $status
    cd "$previous_dir"; or return 1
    return $build_status
end

function install_aur_packages --argument-names helper
    set -l packages $argv[2..-1]
    if test (count $packages) -eq 0
        return 0
    end
    if test "$bootstrap_dry_run" -eq 0; and test $approve_aur -ne 1
        echo "error: --approve-aur is required after reviewing every requested AUR PKGBUILD" >&2
        return 1
    end

    set -l args -S --needed
    if test "$bootstrap_noconfirm" -eq 1
        set -a args --noconfirm
    end
    run "$helper" $args $packages
end

function missing_installed_packages
    for package in $argv
        if not pacman -Q -- "$package" >/dev/null 2>&1
            printf '%s\n' "$package"
        end
    end
end

set -g cutover_active 0
set -g cutover_cli_path
set -g cutover_cli_backup
set -g cutover_cli_had_previous 0
set -g cutover_legacy_journal

function rollback_cutover
    if test $cutover_active -ne 1
        return 0
    end

    set -l rollback_status 0
    clear_legacy_completion_marker "$cutover_legacy_journal"; or set rollback_status 1
    restore_migrated_legacy_links; or set rollback_status 1
    restore_cli_config "$cutover_cli_path" "$cutover_cli_backup" $cutover_cli_had_previous; or set rollback_status 1
    set -g cutover_active 0
    return $rollback_status
end

function bootstrap_interrupt --on-signal INT
    if test $cutover_active -eq 1
        log "interrupt received; rolling back the in-progress configuration cutover"
        rollback_cutover
    end
    exit 130
end

function bootstrap_terminate --on-signal TERM
    if test $cutover_active -eq 1
        log "termination received; rolling back the in-progress configuration cutover"
        rollback_cutover
    end
    exit 143
end

function bootstrap_hangup --on-signal HUP
    if test $cutover_active -eq 1
        log "hangup received; rolling back the in-progress configuration cutover"
        rollback_cutover
    end
    exit 129
end

set -l target_user (profile_scalar "$profile_file" profile user "")
set -l group_user (profile_scalar "$profile_file" groups user "$target_user")
set -l dots_url (profile_scalar "$profile_file" caelestia dots_url "")
set -l dots_branch (profile_scalar "$profile_file" caelestia dots_branch "")
set -l aur_helper (profile_scalar "$profile_file" caelestia aur_helper yay)
if test -n "$helper_override"
    set aur_helper "$helper_override"
end

set -l core_components (profile_array "$profile_file" caelestia core_components)
set -l all_components (profile_array "$profile_file" caelestia enable_components)
set -l official_core (profile_packages_group "$profile_file" official core)
set -l aur_core (profile_packages_group "$profile_file" aur shell)
set -l requested_services (profile_array "$profile_file" services requested)
set -l requested_groups (profile_array "$profile_file" groups requested)
set -l available_package_groups (profile_package_groups "$profile_file")
set -l all_profile_packages
for package_group in $available_package_groups
    set -l group_fields (string split -m 1 . -- "$package_group")
    set -a all_profile_packages (profile_packages_group "$profile_file" $group_fields[1] $group_fields[2])
end
set all_profile_packages (unique_values $all_profile_packages)

set -l official_targets
set -l aur_targets
set -l selected_components
set -l install_components 0
switch "$stage"
    case core
        set official_targets (unique_values $official_core)
        set aur_targets (unique_values $aur_core)
        set selected_components $core_components
        set install_components 1
    case profile
        if test (count $package_groups) -eq 1
            set -l package_group $package_groups[1]
            if not string match -qr '^(official|aur)\.[A-Za-z0-9_-]+$' -- "$package_group"; or not contains -- "$package_group" $available_package_groups
                echo "error: unknown package group '$package_group'; available groups: "(string join ', ' $available_package_groups) >&2
                exit 2
            end
            set -l group_fields (string split -m 1 . -- "$package_group")
            set -l group_packages (profile_packages_group "$profile_file" $group_fields[1] $group_fields[2])
            if test "$group_fields[1]" = official
                set official_targets (unique_values $group_packages)
            else
                set aur_targets (unique_values $group_packages)
            end
        else if test $sync_profile_components -eq 1
            if test "$bootstrap_dry_run" -eq 0; and test $approve_aur -ne 1
                echo "error: --sync-profile-components requires --approve-aur after reviewing all component and local-package sources" >&2
                exit 2
            end
            if test "$bootstrap_dry_run" -eq 1
                log "would require every profile package group to be installed before component sync"
            else
                set -l missing_packages (missing_installed_packages $all_profile_packages)
                if test (count $missing_packages) -gt 0
                    echo "error: install every profile package group before component sync; missing: "(string join ', ' $missing_packages) >&2
                    exit 1
                end
            end
            set selected_components $all_components
            set install_components 1
        end
end

if test -z "$target_user"; or test -z "$dots_url"; or test -z "$dots_branch"
    echo "error: profile user and Caelestia dots source must be explicit" >&2
    exit 1
end

for group in $approved_groups
    if not contains -- "$group" $requested_groups
        echo "error: group '$group' is not requested by the profile" >&2
        exit 2
    end
end

for service in $enabled_services
    if not contains -- "$service" $requested_services
        echo "error: service '$service' is not requested by the profile" >&2
        exit 2
    end
end

log "profile: $profile_file"
log "stage: $stage"
log "target user: $target_user"
log "AUR helper: $aur_helper"
log_list "official targets" $official_targets
log_list "AUR targets" $aur_targets
log_list "Caelestia components" $selected_components
log "requested services (not changed without --enable-service): "(string join ', ' $requested_services)
log "requested groups (not changed without --approve-group): "(string join ', ' $requested_groups)

if test "$bootstrap_dry_run" -eq 0
    if test (id -un) != "$target_user"
        echo "error: profile is for '$target_user', but current user is '"(id -un)"'" >&2
        exit 1
    end
    require_tty; or exit 1
end

validate_fully_updated; or exit 1

if test (count $official_targets) -gt 0
    set -l pacman_args pacman -S --needed
    if test "$bootstrap_noconfirm" -eq 1
        set -a pacman_args --noconfirm
    end
    sudo_run_inhibited $pacman_args $official_targets; or exit 1
end

if test (count $aur_targets) -gt 0
    install_aur_helper "$aur_helper"; or exit 1
    install_aur_packages "$aur_helper" $aur_targets; or exit 1
end

if test $install_components -eq 1
    set -l config_home (set -q XDG_CONFIG_HOME; and echo "$XDG_CONFIG_HOME"; or echo "$HOME/.config")
    set -l cli_path "$config_home/caelestia/cli.json"
    set -l cli_backup
    set -l cli_had_previous 0

    if test "$bootstrap_dry_run" -eq 1
        log "would atomically update ~/.config/caelestia/cli.json to $dots_url#$dots_branch"
    else
        if not command -q caelestia
            echo "error: caelestia-cli is unavailable after core package installation" >&2
            exit 1
        end
        if test -L "$cli_path"; or begin
                test -e "$cli_path"; and not test -f "$cli_path"
            end
            echo "error: refusing to replace a symlink or non-regular CLI config: $cli_path" >&2
            exit 1
        end
        mkdir -p (dirname "$cli_path"); or exit 1
        if test -f "$cli_path"
            set cli_backup (mktemp (dirname "$cli_path")/.cli.json.pre-bootstrap.XXXXXX); or exit 1
            command cp --preserve=mode -- "$cli_path" "$cli_backup"; or exit 1
            set cli_had_previous 1
        end
        set -g cutover_cli_path "$cli_path"
        set -g cutover_cli_backup "$cli_backup"
        set -g cutover_cli_had_previous $cli_had_previous
        set -g cutover_active 1

        python -c '
import json
import os
import stat
import sys
import tempfile
from pathlib import Path

url, branch = sys.argv[1], sys.argv[2]
config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
path = config_home / "caelestia" / "cli.json"
path.parent.mkdir(parents=True, exist_ok=True)
if path.exists():
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("existing CLI config must contain a JSON object")
    mode = stat.S_IMODE(path.stat().st_mode)
else:
    data = {}
    mode = 0o600
if "dots" in data and not isinstance(data["dots"], dict):
    raise ValueError("existing CLI config dots value must contain a JSON object")
data.setdefault("dots", {})
data["dots"]["url"] = url
data["dots"]["branch"] = branch
fd, temporary = tempfile.mkstemp(prefix=".cli.json.", dir=path.parent, text=True)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as stream:
        os.fchmod(stream.fileno(), mode)
        json.dump(data, stream, indent=4, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)
    directory_fd = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)
except BaseException:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
    raise
' "$dots_url" "$dots_branch"; or begin
            rollback_cutover
            exit 1
        end
    end

    if test $migrate_legacy_links -eq 1
        migrate_allowlisted_legacy_links "$legacy_link_journal"; or begin
            rollback_cutover
            exit 1
        end
        set -g cutover_legacy_journal "$legacy_link_journal"
    end

    set -l install_args install --aur-helper "$aur_helper" --enable-components (string join , $selected_components)
    if test "$bootstrap_noconfirm" -eq 1
        set -a install_args --noconfirm
    end
    run_inhibited caelestia $install_args
    set -l install_status $status
    if test $install_status -ne 0
        rollback_cutover
        exit $install_status
    end
    if not validate_migrated_replacements
        rollback_cutover
        exit 1
    end
    if test $migrate_legacy_links -eq 1
        mark_legacy_journal_complete "$legacy_link_journal"; or begin
            rollback_cutover
            exit 1
        end
    end
    set -g cutover_active 0
    if test "$bootstrap_dry_run" -eq 0; and test -n "$cli_backup"
        command rm -f -- "$cli_backup"
    end
end

for service in $enabled_services
    sudo_run systemctl enable "$service"; or exit 1
    sudo_run systemctl start "$service"; or begin
        echo "error: $service was enabled but did not start; inspect it before continuing" >&2
        exit 1
    end
end

for group in $approved_groups
    if not getent group "$group" >/dev/null
        echo "error: approved group '$group' does not exist" >&2
        exit 1
    end
    sudo_run usermod -aG "$group" "$group_user"; or exit 1
end

log "stage complete; no OS upgrade or implicit recursive package cleanup was performed by this bootstrap"
