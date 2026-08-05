function profile_path --argument-names profile
    set -l root (realpath (status dirname)/../..)
    set -l path "$root/profiles/$profile.toml"
    test -r "$path"; or return 1
    printf '%s\n' "$path"
end

function profile_scalar --argument-names file section key fallback
    set -l value (awk -v section="$section" -v key="$key" '
        $0 == "[" section "]" { active = 1; next }
        /^\[/ { active = 0 }
        active && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            sub("^[^=]*=[[:space:]]*", "")
            gsub("^[[:space:]]*\"|\"[[:space:]]*$", "")
            print
            exit
        }
    ' "$file")

    if test -n "$value"
        printf '%s\n' "$value"
    else if test -n "$fallback"
        printf '%s\n' "$fallback"
    end
end

function profile_array --argument-names file section key
    awk -v section="$section" -v key="$key" '
        function emit(line) {
            while (match(line, /"[^"]+"/)) {
                value = substr(line, RSTART + 1, RLENGTH - 2)
                print value
                line = substr(line, RSTART + RLENGTH)
            }
        }

        $0 == "[" section "]" { active = 1; in_array = 0; next }
        /^\[/ { active = 0; in_array = 0 }
        active && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
            in_array = 1
            emit($0)
            if ($0 ~ /\]/) in_array = 0
            next
        }
        active && in_array {
            emit($0)
            if ($0 ~ /\]/) in_array = 0
        }
    ' "$file"
end

function profile_packages --argument-names file source
    awk -v prefix="packages."$source"." '
        function emit(line) {
            while (match(line, /"[^"]+"/)) {
                value = substr(line, RSTART + 1, RLENGTH - 2)
                print value
                line = substr(line, RSTART + RLENGTH)
            }
        }

        /^\[packages\./ {
            section = substr($0, 2, length($0) - 2)
            active = index(section, prefix) == 1
            in_array = 0
            next
        }
        /^\[/ { active = 0; in_array = 0 }
        active && /^[[:space:]]*packages[[:space:]]*=/ {
            in_array = 1
            emit($0)
            if ($0 ~ /\]/) in_array = 0
            next
        }
        active && in_array {
            emit($0)
            if ($0 ~ /\]/) in_array = 0
        }
    ' "$file" | sort -u
end
