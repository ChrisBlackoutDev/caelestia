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
        sudo $argv
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

set -l aur_helper (profile_scalar "$profile_file" caelestia aur_helper paru)
set -l target_user (profile_scalar "$profile_file" groups user (whoami))
set -l dots_url (profile_scalar "$profile_file" caelestia dots_url "https://github.com/ChrisBlackoutDev/caelestia.git")
set -l dots_branch (profile_scalar "$profile_file" caelestia dots_branch "codex/upstream-refresh-2026-08-05")
set -l official_packages (profile_packages "$profile_file" official)
set -l aur_packages (profile_packages "$profile_file" aur)
set -l services (profile_array "$profile_file" services enable)
set -l groups (profile_array "$profile_file" groups add)
set -l components (profile_array "$profile_file" caelestia enable_components)

log "profile: $profile_file"
log "installing official packages"
if test (count $official_packages) -gt 0
    sudo_run pacman -S --needed --noconfirm $official_packages
end

if not command -q $aur_helper
    log "installing AUR helper: $aur_helper"
    sudo_run pacman -S --needed --noconfirm base-devel git
    set -l helper_dir "$HOME/.cache/aur/$aur_helper"
    if test $dry_run -eq 1
        log "would clone/build https://aur.archlinux.org/$aur_helper.git in $helper_dir"
    else
        mkdir -p (dirname "$helper_dir")
        if test -d "$helper_dir/.git"
            git -C "$helper_dir" pull --ff-only
        else
            git clone "https://aur.archlinux.org/$aur_helper.git" "$helper_dir"
        end
        command pushd "$helper_dir" >/dev/null
        makepkg -si --noconfirm
        command popd >/dev/null
    end
end

set -l aur_to_install (filter_helper_packages $aur_helper $aur_packages)
if test (count $aur_to_install) -gt 0
    log "installing AUR packages with $aur_helper"
    run $aur_helper -S --needed --noconfirm $aur_to_install
end

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
' "$dots_url" "$dots_branch"
end

if command -q caelestia
    log "installing Caelestia components"
    set -l install_args install --aur-helper $aur_helper --enable-components (string join , $components)
    if test $noconfirm -eq 1
        set -a install_args --noconfirm
    end
    run caelestia $install_args
else
    log "caelestia-cli not found yet; skipping caelestia install"
end

if test (count $services) -gt 0
    log "enabling services"
    for service in $services
        sudo_run systemctl enable --now $service
    end
end

if test (count $groups) -gt 0
    log "adding $target_user to groups"
    for group in $groups
        if getent group $group >/dev/null
            sudo_run usermod -aG $group $target_user
        else
            log "group not present, skipping: $group"
        end
    end
end

log "done"
