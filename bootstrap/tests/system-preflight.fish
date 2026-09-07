#!/usr/bin/env fish

set -g bootstrap_dry_run 0
set -g mock_query_status 1
set -g mock_pending
set -g mock_query_error
set -g mock_mismatch 0

set -l repo_root (realpath (status dirname)/../..)
source "$repo_root/bootstrap/lib/system.fish"

function log
    printf '[system-preflight-test] %s\n' "$argv"
end

function fail --argument-names message
    echo "error: assertion failed: $message" >&2
    exit 1
end

function bootstrap_pacman
    if test "$argv[1]" = -Qu
        if test (count $mock_pending) -gt 0
            printf '%s\n' $mock_pending
        end
        if test -n "$mock_query_error"
            printf '%s\n' "$mock_query_error" >&2
        end
        return $mock_query_status
    end
    if test "$argv[1]" = -Q
        set -l package $argv[-1]
        set -l mock_version 1.0-1
        if test $mock_mismatch -eq 1; and test "$package" = libnm
            set mock_version 2.0-1
        end
        printf '%s %s\n' "$package" "$mock_version"
        return 0
    end
    return 2
end

if not validate_fully_updated
    fail 'empty status-1 upgrade query was rejected'
end

set mock_query_status 2
if validate_fully_updated
    fail 'unexpected pacman query failure was accepted'
end

set mock_query_status 1
set mock_query_error 'error: package database is unavailable'
if validate_fully_updated
    fail 'status-1 pacman query error was accepted'
end

set mock_query_error
set mock_query_status 0
set mock_pending example-package\ 2.0-1
if validate_fully_updated
    fail 'pending upgrade output was accepted'
end

set mock_pending
set mock_query_status 1
set mock_mismatch 1
if validate_fully_updated
    fail 'runtime cohort version mismatch was accepted'
end

printf 'system-preflight-tests=passed scenarios=5\n'
