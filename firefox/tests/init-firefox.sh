#!/usr/bin/env bash

set -Eeuo pipefail

repo_root=$(realpath "$(dirname "$0")/../..")
test_root=$(mktemp -d)
cleanup_test_root() {
    [[ -d "$test_root" && ! -L "$test_root" ]] || return 0
    rm -r -- "$test_root"
}
trap cleanup_test_root EXIT
fake_bin="$test_root/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/firefox" <<'FAKE'
#!/usr/bin/env bash
set -Eeuo pipefail
printf '%s\n' "$@" >"$FAKE_FIREFOX_ARGS"
printf '%s\n' "${DBUS_SESSION_BUS_ADDRESS:-}" >"$FAKE_FIREFOX_DBUS"
if [[ "${FAKE_FIREFOX_NO_WRITE:-0}" == 1 ]]; then
    exit 0
fi
[[ "$1" == --headless ]]
[[ "$2" == --no-remote ]]
[[ "$3" == about:blank ]]
root=$(dirname "$FAKE_FIREFOX_PROFILES_INI")
profile=caelestia-test.default-release
mkdir -p "$root/$profile"
printf '[Profile0]\nName=default-release\nIsRelative=1\nPath=%s\n' "$profile" \
    >"$FAKE_FIREFOX_PROFILES_INI"
printf '[InstallTEST]\nDefault=%s\nLocked=1\n' "$profile" \
    >"$root/installs.ini"
trap 'exit 143' TERM
while :; do
    sleep 0.1
done
FAKE
chmod 700 "$fake_bin/firefox"

run_fixture() {
    local name=$1
    local home="$test_root/$name/home"
    local config="$test_root/$name/config"
    mkdir -p "$home" "$config"
    HOME="$home" \
        XDG_CONFIG_HOME="$config" \
        PATH="$fake_bin:/usr/bin:/bin" \
        FAKE_FIREFOX_ARGS="$test_root/$name/args" \
        FAKE_FIREFOX_DBUS="$test_root/$name/dbus" \
        FAKE_FIREFOX_PROFILES_INI="$config/mozilla/firefox/profiles.ini" \
        bash "$repo_root/firefox/init_firefox.sh"
}

run_fixture xdg
xdg_root="$test_root/xdg/config/mozilla/firefox"
test -f "$xdg_root/profiles.ini"
test -f "$xdg_root/installs.ini"
test -d "$xdg_root/caelestia-test.default-release"
grep -Fx -- '--headless' "$test_root/xdg/args" >/dev/null
grep -Fx -- '--no-remote' "$test_root/xdg/args" >/dev/null
grep -Fx -- 'about:blank' "$test_root/xdg/args" >/dev/null
grep -Fx -- 'unix:path=/dev/null' "$test_root/xdg/dbus" >/dev/null
grep -Fq 'Default=caelestia-test.default-release' "$xdg_root/installs.ini"

existing="$test_root/existing/config/mozilla/firefox"
mkdir -p "$existing"
printf '[Profile0]\n' >"$existing/profiles.ini"
printf '[InstallTEST]\n' >"$existing/installs.ini"
HOME="$test_root/existing/home" \
    XDG_CONFIG_HOME="$test_root/existing/config" \
    PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_FIREFOX_NO_WRITE=1 \
    FAKE_FIREFOX_ARGS="$test_root/existing/args" \
    FAKE_FIREFOX_DBUS="$test_root/existing/dbus" \
    FAKE_FIREFOX_PROFILES_INI="$existing/profiles.ini" \
    bash "$repo_root/firefox/init_firefox.sh"
test ! -e "$test_root/existing/args"

fallback_home="$test_root/fallback/home"
mkdir -p "$fallback_home"
env -u XDG_CONFIG_HOME \
    HOME="$fallback_home" \
    PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_FIREFOX_ARGS="$test_root/fallback/args" \
    FAKE_FIREFOX_DBUS="$test_root/fallback/dbus" \
    FAKE_FIREFOX_PROFILES_INI="$fallback_home/.config/mozilla/firefox/profiles.ini" \
    bash "$repo_root/firefox/init_firefox.sh"
test -f "$fallback_home/.config/mozilla/firefox/profiles.ini"

broken_home="$test_root/broken/home"
broken_config="$test_root/broken/config"
mkdir -p "$broken_home" "$broken_config"
if HOME="$broken_home" \
    XDG_CONFIG_HOME="$broken_config" \
    PATH="$fake_bin:/usr/bin:/bin" \
    FAKE_FIREFOX_NO_WRITE=1 \
    FAKE_FIREFOX_ARGS="$test_root/broken/args" \
    FAKE_FIREFOX_DBUS="$test_root/broken/dbus" \
    FAKE_FIREFOX_PROFILES_INI="$broken_config/mozilla/firefox/profiles.ini" \
    bash "$repo_root/firefox/init_firefox.sh"; then
    printf 'error: missing profiles.ini was accepted\n' >&2
    exit 1
fi

grep -Fq 'dest = "$XDG_CONFIG_HOME/mozilla/firefox/*.default*/chrome/userChrome.css"' \
    "$repo_root/manifest.toml"
grep -Fq 'dest = "$XDG_CONFIG_HOME/mozilla/firefox/*.default*/user.js"' \
    "$repo_root/manifest.toml"
! grep -Fq '.mozilla/firefox' "$repo_root/manifest.toml"

printf 'firefox-init-tests=passed scenarios=4\n'
