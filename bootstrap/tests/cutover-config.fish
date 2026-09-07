#!/usr/bin/env fish

set -l test_root (mktemp -d); or exit 1
set -g bootstrap_dry_run 0
set -l repo_root (realpath (status dirname)/../..)
source "$repo_root/bootstrap/lib/cutover.fish"

function log
    printf '[cutover-test] %s\n' "$argv"
end

function fail --argument-names message
    echo "error: assertion failed: $message" >&2
    exit 1
end

set -l existing "$test_root/existing/cli.json"
mkdir -p (dirname "$existing"); or exit 1
printf '{"before":true}\n' >"$existing"; or exit 1
set -l backup "$test_root/existing/backup.json"
cp -- "$existing" "$backup"; or exit 1
printf '{"after":true}\n' >"$existing"; or exit 1
restore_cli_config "$existing" "$backup" 1; or exit 1
if test (string collect <"$existing") != '{"before":true}'
    fail "existing CLI config was not restored byte-for-byte"
end

set -l newly_created "$test_root/new/cli.json"
mkdir -p (dirname "$newly_created"); or exit 1
touch "$newly_created"; or exit 1
restore_cli_config "$newly_created" '' 0; or exit 1
if test -e "$newly_created"; or test -L "$newly_created"
    fail "new CLI config was not removed during rollback"
end

set -l unsafe "$test_root/unsafe/cli.json"
mkdir -p "$unsafe"; or exit 1
if restore_cli_config "$unsafe" '' 0
    fail "non-regular new CLI config was removed"
end
if not test -d "$unsafe"
    fail "non-regular new CLI config was not preserved"
end

printf 'cutover-config-tests=passed fixture=%s scenarios=3\n' "$test_root"
