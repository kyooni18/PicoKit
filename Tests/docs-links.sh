#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
links=$(mktemp)
raw_links=$(mktemp)
trap 'rm -f "$links" "$raw_links"' EXIT

for document in "$root/README.md" "$root/Docs/00-README.md"; do
    test -s "$document"
    base=$(dirname "$document")
    if ! rg -o --with-filename '\]\([^)]*' "$document" > "$raw_links"; then
        echo "$document contains no readable markdown links" >&2
        exit 1
    fi
    sed -E 's/^[^:]+:\]\((.*)$/\1/; s/#.*$//' "$raw_links" > "$links"
    test -s "$links"
    while IFS= read -r target; do
        if ! test -n "$target"; then
            echo "$document contains an empty markdown link target" >&2
            exit 1
        fi
        case "$target" in
            http://*|https://*|mailto:*) continue ;;
        esac
        if ! test -e "$base/$target"; then
            echo "$document links to missing local path: $target" >&2
            exit 1
        fi
    done < "$links"
done

echo "PicoKit documentation link validation passed"
