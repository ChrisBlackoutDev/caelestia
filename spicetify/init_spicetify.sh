#!/usr/bin/env bash

set -euo pipefail

config_home="${XDG_CONFIG_HOME:-${HOME}/.config}"
prefs_path="${config_home}/spotify/prefs"

mkdir -p "${prefs_path%/*}"
if [[ ! -e "$prefs_path" ]]; then
    printf '%s\n' 'app.autostart-mode="off"' > "$prefs_path"
fi

spicetify config \
    spotify_path /opt/spotify \
    prefs_path "$prefs_path" \
    current_theme caelestia \
    color_scheme caelestia \
    custom_apps marketplace

if [[ ! -w /opt/spotify/Apps ]]; then
    sudo setfacl -R -m "u:${USER}:rwX" /opt/spotify
fi

spicetify backup apply
