#!/usr/bin/env bash

set -Eeuo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
firefox_root="$config_home/mozilla/firefox"
profiles_ini="$firefox_root/profiles.ini"
installs_ini="$firefox_root/installs.ini"

[[ -f "$profiles_ini" && -f "$installs_ini" ]] && exit 0

mkdir -p "$firefox_root"
firefox_pid=
cleanup_firefox() {
    [[ -n "$firefox_pid" ]] || return 0
    kill "$firefox_pid" 2>/dev/null || true
    wait "$firefox_pid" 2>/dev/null || true
}
trap cleanup_firefox EXIT

DBUS_SESSION_BUS_ADDRESS=unix:path=/dev/null MOZ_NO_REMOTE=1 \
    firefox --headless --no-remote about:blank &>/dev/null &
firefox_pid=$!

tries=0
while [[ ! -f "$profiles_ini" || ! -f "$installs_ini" ]]; do
    kill -0 "$firefox_pid" 2>/dev/null || break
    tries=$((tries + 1))
    [[ "$tries" -lt 60 ]] || break
    sleep 0.5
done

killed=0
if kill -0 "$firefox_pid" 2>/dev/null; then
    kill "$firefox_pid" 2>/dev/null || true
    killed=1
fi
set +e
wait "$firefox_pid" 2>/dev/null
wait_status=$?
set -e
firefox_pid=
trap - EXIT

if [[ ! -f "$profiles_ini" || ! -f "$installs_ini" ]]; then
    printf 'error: Firefox did not create %s and %s\n' \
        "$profiles_ini" "$installs_ini" >&2
    exit 1
fi

if [[ "$wait_status" -ne 0 ]] && \
    ! [[ "$killed" -eq 1 && "$wait_status" -eq 143 ]]; then
    printf 'error: Firefox profile initialization exited with status %s\n' \
        "$wait_status" >&2
    exit "$wait_status"
fi
