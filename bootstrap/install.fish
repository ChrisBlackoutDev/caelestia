#!/usr/bin/env fish

set -l root (realpath (status dirname)/..)
source "$root/bootstrap/lib/profile.fish"

set -l profile kensa-desktop
set -l noconfirm 0
set -l dry_run 0

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
        case --noconfirm
            set noconfirm 1
        case --dry-run
            set dry_run 1
        case -h --help
            echo "usage: bootstrap/install.fish [--profile NAME] [--noconfirm] [--dry-run]"
            exit 0
    end
    set i (math $i + 1)
end

set -l profile_file (profile_path $profile)
if test $status -ne 0
    echo "error: profile '$profile' not found under $root/profiles" >&2
    exit 1
end

set -g bootstrap_dry_run $dry_run
set -g reboot_recommended 0
set -g service_start_failures

function log
    printf '[bootstrap] %s\n' "$argv"
end

function run
    if test "$bootstrap_dry_run" -eq 1
        printf '[dry-run] %s\n' (string join -- ' ' (string escape -- $argv))
    else
        command $argv
    end
end

function sudo_run
    if test "$bootstrap_dry_run" -eq 1
        printf '[dry-run] sudo %s\n' (string join -- ' ' (string escape -- $argv))
    else
        set -l sudo_cmd sudo
        if set -q SUDO_ASKPASS
            set sudo_cmd sudo -A
        end
        command $sudo_cmd $argv
    end
end

function sudo_run_inhibited
    if test "$bootstrap_dry_run" -eq 1
        printf '[dry-run] sudo systemd-inhibit --what=idle:sleep:shutdown --why %s %s\n' \
            (string escape -- "Caelestia bootstrap live migration") \
            (string join -- ' ' (string escape -- $argv))
    else if command -q systemd-inhibit
        set -l sudo_cmd sudo
        if set -q SUDO_ASKPASS
            set sudo_cmd sudo -A
        end
        command $sudo_cmd systemd-inhibit --what=idle:sleep:shutdown --why "Caelestia bootstrap live migration" $argv
    else
        set -l sudo_cmd sudo
        if set -q SUDO_ASKPASS
            set sudo_cmd sudo -A
        end
        command $sudo_cmd $argv
    end
end

function run_inhibited
    if test "$bootstrap_dry_run" -eq 1
        printf '[dry-run] systemd-inhibit --what=idle:sleep --why %s %s\n' \
            (string escape -- "Caelestia bootstrap live migration") \
            (string join -- ' ' (string escape -- $argv))
    else if command -q systemd-inhibit
        systemd-inhibit --what=idle:sleep --why "Caelestia bootstrap live migration" $argv
        set -l inhibit_status $status
        if test $inhibit_status -eq 0
            return 0
        end

        log "systemd-inhibit failed with status $inhibit_status; continuing without an idle/sleep inhibitor"
        command $argv
    else
        command $argv
    end
end

function filter_helper_packages
    set -l helper $argv[1]
    for package in $argv[2..-1]
        if test "$package" != "$helper"
            printf '%s\n' "$package"
        end
    end
end

function aur_helper_build_deps --argument-names helper
    switch "$helper"
        case paru
            printf '%s\n' cargo
        case yay
            printf '%s\n' go
    end
end

function built_package_files --argument-names dir
    find "$dir" -maxdepth 1 -type f -name '*.pkg.tar.zst' ! -name '*-debug-*.pkg.tar.zst' -print
end

function package_version --argument-names package
    pacman -Q "$package" 2>/dev/null | string split ' ' -f 2
end

function validate_same_installed_version --argument-names label
    set -l packages $argv[2..-1]
    set -l reference_version
    set -l installed

    for package in $packages
        set -l package_version_value (package_version "$package")
        if test -z "$package_version_value"
            continue
        end

        set -a installed "$package=$package_version_value"
        if test -z "$reference_version"
            set reference_version "$package_version_value"
        else if test "$package_version_value" != "$reference_version"
            echo "error: $label version mismatch detected:" >&2
            for entry in $installed
                echo "  $entry" >&2
            end
            echo "Run 'sudo pacman -Syu' and rerun the bootstrap before live Caelestia migration." >&2
            return 1
        end
    end
end

function validate_split_packages
    if pacman -Q networkmanager >/dev/null 2>&1
        if not pacman -Q libnm >/dev/null 2>&1
            echo "error: networkmanager is installed but libnm is missing." >&2
            echo "Run 'sudo pacman -Syu' and rerun the bootstrap before live Caelestia migration." >&2
            return 1
        end
    end

    validate_same_installed_version "NetworkManager/libnm" networkmanager libnm; or return 1
    validate_same_installed_version "GCC runtime" gcc gcc-libs libgcc libstdc++ lib32-gcc-libs; or return 1
end

function require_installed --argument-names package reason
    if test "$bootstrap_dry_run" -eq 1
        log "would require installed package: $package ($reason)"
        return 0
    end

    if not pacman -Q "$package" >/dev/null 2>&1
        echo "error: required package '$package' is not installed: $reason" >&2
        return 1
    end
end

function validate_live_migration_ready
    validate_split_packages; or return 1
    require_installed hyprlock "Hyprland lock fallback must exist before a live shell/session-lock migration."; or return 1
end

function warn_if_running_kernel_modules_missing
    if test "$bootstrap_dry_run" -eq 1
        return 0
    end

    set -l running_kernel (uname -r)
    if not test -d "/lib/modules/$running_kernel"
        set -g reboot_recommended 1
        log "warning: module tree for running kernel $running_kernel is missing; reboot before starting kernel-module-dependent services such as Docker"
    end
end

function require_tty_for_caelestia_install
    if test "$bootstrap_dry_run" -eq 1
        return 0
    end

    if not test -t 0
        echo "error: live caelestia install requires a TTY because caelestia-cli may invoke sudo internally." >&2
        echo "Rerun over SSH with a pseudo-terminal, for example: ssh -tt <host> 'cd ~/.local/share/caelestia && fish bootstrap/install.fish --profile $profile --noconfirm'" >&2
        return 1
    end
end

function remove_installed_packages --argument-names label
    set -l packages $argv[2..-1]
    set -l installed
    for package in $packages
        if pacman -Q "$package" >/dev/null 2>&1
            set -a installed "$package"
        end
    end

    if test (count $installed) -gt 0
        log "removing $label packages: "(string join ', ' $installed)
        sudo_run pacman -Rns --noconfirm $installed; or return 1
    end
end

set -l aur_helper (profile_scalar "$profile_file" caelestia aur_helper paru)
set -l target_user (profile_scalar "$profile_file" groups user (whoami))
set -l dots_url (profile_scalar "$profile_file" caelestia dots_url "https://github.com/ChrisBlackoutDev/caelestia.git")
set -l dots_branch (profile_scalar "$profile_file" caelestia dots_branch "codex/upstream-refresh-2026-08-05")
set -l official_packages (profile_packages "$profile_file" official)
set -l aur_packages (profile_packages "$profile_file" aur)
set -l cleanup_before_packages (profile_array "$profile_file" packages.cleanup remove_before_install)
set -l cleanup_after_packages (profile_array "$profile_file" packages.cleanup remove_after_install)
set -l services (profile_array "$profile_file" services enable)
set -l groups (profile_array "$profile_file" groups add)
set -l components (profile_array "$profile_file" caelestia enable_components)

log "profile: $profile_file"

log "running full Arch system upgrade preflight"
set -l system_upgrade_args pacman -Syu
if test $noconfirm -eq 1
    set -a system_upgrade_args --noconfirm
end
sudo_run_inhibited $system_upgrade_args; or exit 1
validate_split_packages; or exit 1
warn_if_running_kernel_modules_missing

remove_installed_packages profile-preinstall-cleanup $cleanup_before_packages; or exit 1

log "installing official packages"
if test (count $official_packages) -gt 0
    sudo_run pacman -S --needed --noconfirm $official_packages; or exit 1
end
remove_installed_packages profile-postinstall-cleanup $cleanup_after_packages; or exit 1
validate_live_migration_ready; or exit 1

if not command -q $aur_helper
    log "installing AUR helper: $aur_helper"
    sudo_run pacman -S --needed --noconfirm base-devel git; or exit 1
    set -l helper_build_deps (aur_helper_build_deps $aur_helper)
    if test (count $helper_build_deps) -gt 0
        sudo_run pacman -S --needed --noconfirm $helper_build_deps; or exit 1
    end

    set -l helper_dir "$HOME/.cache/aur/$aur_helper"
    if test $dry_run -eq 1
        log "would clone/build https://aur.archlinux.org/$aur_helper.git in $helper_dir"
    else
        mkdir -p (dirname "$helper_dir"); or exit 1
        if test -d "$helper_dir/.git"
            git -C "$helper_dir" pull --ff-only; or exit 1
        else
            git clone "https://aur.archlinux.org/$aur_helper.git" "$helper_dir"; or exit 1
        end
        set -l previous_dir (pwd)
        cd "$helper_dir"; or exit 1
        makepkg --noconfirm
        set -l makepkg_status $status
        cd "$previous_dir"; or exit 1
        test $makepkg_status -eq 0; or exit $makepkg_status

        set -l helper_packages (built_package_files "$helper_dir")
        if test (count $helper_packages) -eq 0
            echo "error: no built package found for AUR helper '$aur_helper' in $helper_dir" >&2
            exit 1
        end
        sudo_run pacman -U --needed --noconfirm $helper_packages; or exit 1
    end
end

set -l aur_to_install (filter_helper_packages $aur_helper $aur_packages)
if test (count $aur_to_install) -gt 0
    log "installing AUR packages with $aur_helper"
    set -l aur_install_args -S --needed --noconfirm
    if test "$aur_helper" = paru
        set -a aur_install_args --skipreview --noinstalldebug
        if set -q SUDO_ASKPASS
            set -a aur_install_args --sudoflags=-A
        end
    end
    run $aur_helper $aur_install_args $aur_to_install; or exit 1
end
validate_live_migration_ready; or exit 1

log "writing caelestia CLI dots source"
if test $dry_run -eq 1
    log "would update ~/.config/caelestia/cli.json for $dots_url#$dots_branch"
else
    python -c '
import json
import os
import sys
from pathlib import Path

url, branch = sys.argv[1], sys.argv[2]
config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
path = config_home / "caelestia" / "cli.json"
path.parent.mkdir(parents=True, exist_ok=True)
try:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        data = {}
except (OSError, json.JSONDecodeError):
    data = {}
data.setdefault("dots", {})
data["dots"]["url"] = url
data["dots"]["branch"] = branch
path.write_text(json.dumps(data, indent=4, sort_keys=True) + "\n", encoding="utf-8")
' "$dots_url" "$dots_branch"; or exit 1
end

if command -q caelestia
    validate_live_migration_ready; or exit 1
    require_tty_for_caelestia_install; or exit 1
    log "installing Caelestia components"
    if test -n "$HYPRLAND_INSTANCE_SIGNATURE"
        log "Hyprland is running; keep this session unlocked until the Caelestia install finishes."
        log "systemd idle/sleep/shutdown inhibition is active where supported, but compositor idle lockers may still trigger."
    end
    set -l install_args install --aur-helper $aur_helper --enable-components (string join , $components)
    if test $noconfirm -eq 1
        set -a install_args --noconfirm
    end
    run_inhibited caelestia $install_args; or exit 1
else
    log "caelestia-cli not found yet; skipping caelestia install"
end
validate_live_migration_ready; or exit 1

if test (count $services) -gt 0
    log "enabling services"
    for service in $services
        sudo_run systemctl enable $service; or exit 1
        if not sudo_run systemctl start $service
            set -a service_start_failures "$service"
            log "warning: service enabled but failed to start now: $service"
        end
    end
end

if test (count $groups) -gt 0
    log "adding $target_user to groups"
    for group in $groups
        if getent group $group >/dev/null
            sudo_run usermod -aG $group $target_user; or exit 1
        else
            log "group not present, skipping: $group"
        end
    end
end

if test (count $service_start_failures) -gt 0
    log "services needing manual check or reboot before start: "(string join ', ' $service_start_failures)
end

if test "$reboot_recommended" -eq 1
    log "reboot recommended before validating Docker, kernel modules, or a graphical login"
end

log "done"
