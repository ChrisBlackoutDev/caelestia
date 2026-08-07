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
        printf '[dry-run] systemd-inhibit --what=idle --why %s %s\n' \
            (string escape -- "Caelestia bootstrap live migration") \
            (string join -- ' ' (string escape -- $argv))
    else if command -q systemd-inhibit
        systemd-inhibit --what=idle --why "Caelestia bootstrap live migration" $argv
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

function install_root_text_file --argument-names destination
    set -l lines $argv[2..-1]

    if test "$bootstrap_dry_run" -eq 1
        printf '[dry-run] write %s\n' "$destination"
        for line in $lines
            printf '[dry-run]   %s\n' "$line"
        end
        return 0
    end

    set -l tmp (mktemp); or return 1
    for line in $lines
        printf '%s\n' "$line" >>"$tmp"; or begin
            command rm -f "$tmp"
            return 1
        end
    end

    sudo_run install -m 644 "$tmp" "$destination"
    set -l install_status $status
    command rm -f "$tmp"
    return $install_status
end

function install_sudoers_file --argument-names destination
    set -l lines $argv[2..-1]

    if test "$bootstrap_dry_run" -eq 1
        printf '[dry-run] validate and write sudoers %s\n' "$destination"
        for line in $lines
            printf '[dry-run]   %s\n' "$line"
        end
        return 0
    end

    set -l tmp (mktemp); or return 1
    for line in $lines
        printf '%s\n' "$line" >>"$tmp"; or begin
            command rm -f "$tmp"
            return 1
        end
    end

    sudo_run visudo -cf "$tmp"; or begin
        command rm -f "$tmp"
        return 1
    end

    sudo_run install -m 440 "$tmp" "$destination"
    set -l install_status $status
    command rm -f "$tmp"
    return $install_status
end

function configure_browser_policy_dirs
    set -l browsers \
        chromium /etc/chromium/policies/managed \
        brave /etc/brave/policies/managed \
        google-chrome-stable /etc/opt/chrome/policies/managed

    set -l i 1
    while test $i -le (count $browsers)
        set -l browser $browsers[$i]
        set -l policy_dir $browsers[(math $i + 1)]
        set i (math $i + 2)

        if command -q "$browser"
            sudo_run install -d -m 755 "$policy_dir"; or return 1
        end
    end
end

function configure_caelestia_theme_privileges --argument-names user
    if test -z "$user"
        return 0
    end

    if not string match -qr '^[A-Za-z0-9_.-]+$' -- "$user"
        echo "error: refusing to write sudoers rule for unsupported user name '$user'" >&2
        return 1
    end

    log "configuring Caelestia theme root helpers"
    configure_browser_policy_dirs; or return 1
    install_sudoers_file /etc/sudoers.d/caelestia-theme \
        "# Managed by ChrisBlackoutDev Caelestia bootstrap." \
        "# Allows caelestia-cli theme updates to run their exact noninteractive root hooks without login-time sudo prompts." \
        "Cmnd_Alias CAELESTIA_PAPIRUS_FOLDERS = /usr/bin/papirus-folders -C * -u" \
        "Cmnd_Alias CAELESTIA_BROWSER_POLICY_DIRS = /usr/bin/mkdir -p /etc/chromium/policies/managed, /usr/bin/mkdir -p /etc/brave/policies/managed, /usr/bin/mkdir -p /etc/opt/chrome/policies/managed" \
        "Cmnd_Alias CAELESTIA_BROWSER_POLICY_FILES = /usr/bin/tee /etc/chromium/policies/managed/caelestia.json, /usr/bin/tee /etc/brave/policies/managed/caelestia.json, /usr/bin/tee /etc/opt/chrome/policies/managed/caelestia.json" \
        "$user ALL=(root) NOPASSWD: CAELESTIA_PAPIRUS_FOLDERS, CAELESTIA_BROWSER_POLICY_DIRS, CAELESTIA_BROWSER_POLICY_FILES"; or return 1
end

function ensure_sddm_theme_wrapper --argument-names theme source_theme config_file
    if test -z "$theme"; or test -z "$source_theme"; or test -z "$config_file"
        return 0
    end

    if test "$theme" = "$source_theme"
        return 0
    end

    set -l theme_dir "/usr/share/sddm/themes/$theme"
    set -l source_dir "/usr/share/sddm/themes/$source_theme"

    if test -d "$theme_dir"
        return 0
    end

    if test "$bootstrap_dry_run" -eq 0
        if not test -d "$source_dir"
            echo "error: SDDM source theme '$source_theme' is configured, but $source_dir does not exist." >&2
            return 1
        end
        if not test -f "$source_dir/$config_file"
            echo "error: SDDM source config '$config_file' is configured, but $source_dir/$config_file does not exist." >&2
            return 1
        end
    end

    log "creating SDDM theme wrapper: $theme from $source_theme#$config_file"
    sudo_run install -d -m 755 "$theme_dir"; or return 1

    for entry in Assets Backgrounds Components Fonts Main.qml Previews Themes
        if test "$bootstrap_dry_run" -eq 1
            printf '[dry-run] sudo ln -sfn %s %s\n' \
                (string escape -- "../$source_theme/$entry") \
                (string escape -- "$theme_dir/$entry")
        else if test -e "$source_dir/$entry"
            sudo_run ln -sfn "../$source_theme/$entry" "$theme_dir/$entry"; or return 1
        end
    end

    install_root_text_file "$theme_dir/metadata.desktop" \
        "[SddmGreeterTheme]" \
        "Name=Pixel Sakura" \
        "Description=Pixel Sakura variant of Keyitdev's sddm-astronaut-theme" \
        "Author=keyitdev" \
        "Website=https://github.com/Keyitdev/sddm-astronaut-theme" \
        "License=GPL-3.0-or-later" \
        "Type=sddm-theme" \
        "Version=1.4" \
        "ConfigFile=$config_file" \
        "MainScript=Main.qml" \
        "TranslationsDirectory=translations" \
        "Theme-Id=$theme" \
        "Theme-API=2.0" \
        "QtVersion=6"; or return 1
end

function configure_sddm --argument-names theme input_method source_theme config_file
    if test -z "$theme"; and test -z "$input_method"
        return 0
    end

    log "configuring SDDM"
    sudo_run install -d -m 755 /etc/sddm.conf.d; or return 1

    if test -n "$theme"
        ensure_sddm_theme_wrapper "$theme" "$source_theme" "$config_file"; or return 1

        if test "$bootstrap_dry_run" -eq 0
            if not test -d "/usr/share/sddm/themes/$theme"
                echo "error: SDDM theme '$theme' is configured, but /usr/share/sddm/themes/$theme does not exist." >&2
                echo "Install the configured theme package and rerun the bootstrap." >&2
                return 1
            end
        end

        install_root_text_file /etc/sddm.conf.d/theme.conf "[Theme]" "Current=$theme"; or return 1
    end

    if test -n "$input_method"
        install_root_text_file /etc/sddm.conf.d/virtualkbd.conf "[General]" "InputMethod=$input_method"; or return 1
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
set -l sddm_theme (profile_scalar "$profile_file" display_manager.sddm theme "")
set -l sddm_source_theme (profile_scalar "$profile_file" display_manager.sddm source_theme "")
set -l sddm_config_file (profile_scalar "$profile_file" display_manager.sddm config_file "")
set -l sddm_input_method (profile_scalar "$profile_file" display_manager.sddm input_method "")

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
configure_caelestia_theme_privileges "$target_user"; or exit 1
configure_sddm "$sddm_theme" "$sddm_input_method" "$sddm_source_theme" "$sddm_config_file"; or exit 1

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
