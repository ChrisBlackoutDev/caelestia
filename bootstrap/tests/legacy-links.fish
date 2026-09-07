#!/usr/bin/env fish

set -g legacy_test_root (mktemp -d); or exit 1
set -g bootstrap_dry_run 0

set -l repo_root (realpath (status dirname)/../..)
source "$repo_root/bootstrap/lib/legacy.fish"

function log
    printf '[legacy-test] %s\n' "$argv"
end

function fail --argument-names message
    echo "error: assertion failed: $message" >&2
    exit 1
end

function assert --argument-names message
    command $argv[2..-1]; or fail "$message"
end

function prepare_fixture --argument-names name
    set -gx HOME "$legacy_test_root/$name/home"
    set -gx XDG_CONFIG_HOME "$HOME/.config"
    set -gx XDG_DATA_HOME "$HOME/.local/share"
    set -l legacy "$HOME/.local/share/caelestia"
    mkdir -p "$legacy"; or exit 1
    git -C "$legacy" init -q; or exit 1
    git -C "$legacy" remote add origin https://github.com/ChrisBlackoutDev/caelestia.git; or exit 1

    for pair in (legacy_link_pairs)
        set -l fields (string split \t -- "$pair")
        set -l path $fields[1]
        set -l target $fields[2]
        mkdir -p (dirname "$path") (dirname "$target"); or exit 1
        touch "$target"; or exit 1
        ln -s "$target" "$path"; or exit 1
    end
end

function assert_all_live_links
    for pair in (legacy_link_pairs)
        set -l fields (string split \t -- "$pair")
        assert "legacy link exists at $fields[1]" test -L "$fields[1]"
        assert "legacy link target is exact at $fields[1]" test (readlink -- "$fields[1]") = "$fields[2]"
    end
end

prepare_fixture normal
set -l journal "$HOME/cutover-journal"
mkdir -p "$journal"; or exit 1
migrate_allowlisted_legacy_links "$journal"; or exit 1
assert "all allowlisted paths were tracked" test (count $migrated_legacy_paths) -eq 11
for pair in (legacy_link_pairs)
    set -l path (string split \t -- "$pair")[1]
    set -l saved "$journal/"(string replace -- "$HOME/" '' "$path")
    assert "live legacy link was moved" test ! -L "$path"
    assert "journal contains saved link" test -L "$saved"
end
restore_migrated_legacy_links; or exit 1
assert_all_live_links

prepare_fixture wrong-target
set journal "$HOME/cutover-journal"
mkdir -p "$journal"; or exit 1
set -l bad_path "$XDG_CONFIG_HOME/btop"
unlink "$bad_path"; or exit 1
ln -s "$HOME/unrecognized-target" "$bad_path"; or exit 1
if migrate_allowlisted_legacy_links "$journal"
    fail "mismatched legacy target was accepted"
end
for pair in (legacy_link_pairs)
    set -l path (string split \t -- "$pair")[1]
    assert "failed preflight moved no live link at $path" test -L "$path"
end

prepare_fixture mid-move-failure
set journal "$HOME/cutover-journal"
mkdir -p "$journal"; or exit 1
# The first eight destinations use .config; this blocks the later .local mkdir.
touch "$journal/.local"; or exit 1
if migrate_allowlisted_legacy_links "$journal"
    fail "migration unexpectedly survived an injected destination mkdir failure"
end
assert_all_live_links
assert "failed migration cleared in-memory move state" test (count $migrated_legacy_paths) -eq 0

prepare_fixture retry-and-recovery
set journal "$HOME/cutover-journal"
mkdir -p "$journal"; or exit 1
migrate_allowlisted_legacy_links "$journal"; or exit 1
set -g migrated_legacy_paths
# Simulate a new process discovering durable saved links after interruption.
migrate_allowlisted_legacy_links "$journal"; or exit 1
assert "retry rediscovered every saved link" test (count $migrated_legacy_paths) -eq 11
for pair in (legacy_link_pairs)
    set -l path (string split \t -- "$pair")[1]
    mkdir -p (dirname "$path"); or exit 1
    touch "$path"; or exit 1
end
restore_migrated_legacy_links; or exit 1
assert_all_live_links
set -l recovery_roots $journal/failed-replacements-*
assert "rollback created exactly one recovery tree" test (count $recovery_roots) -eq 1
set -l recovered_count (find "$recovery_roots[1]" -type f | count)
assert "rollback preserved every partial replacement" test "$recovered_count" -eq 11
assert "durable expected-link manifest remains" test -f "$journal/expected.tsv"

prepare_fixture completed-journal
set journal "$HOME/cutover-journal"
mkdir -p "$journal"; or exit 1
migrate_allowlisted_legacy_links "$journal"; or exit 1
for pair in (legacy_link_pairs)
    set -l path (string split \t -- "$pair")[1]
    mkdir -p (dirname "$path"); or exit 1
    touch "$path"; or exit 1
end
validate_migrated_replacements; or exit 1
mark_legacy_journal_complete "$journal"; or exit 1
assert "successful cutover wrote a regular completion marker" test -f "$journal/COMPLETED"
if migrate_allowlisted_legacy_links "$journal"
    fail "completed cutover journal was reusable"
end

printf 'legacy-link-tests=passed fixture=%s scenarios=5\n' "$legacy_test_root"
