#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/Tests" "$tmp/Docs"
cp "$root/Tests/docs-links.sh" "$tmp/Tests/docs-links.sh"
printf '%s\n' '# Fixture' > "$tmp/README.md"
printf '%s\n' '# Fixture docs' > "$tmp/Docs/README.md"

if (cd "$tmp" && sh Tests/docs-links.sh); then
    echo "documentation link checker accepted missing links" >&2
    exit 1
fi

printf '%s\n' '# Fixture' 'See []().' > "$tmp/README.md"
printf '%s\n' '# Fixture docs' '[Guide](../README.md)' > "$tmp/Docs/README.md"

if (cd "$tmp" && sh Tests/docs-links.sh); then
    echo "documentation link checker accepted an empty target" >&2
    exit 1
fi

printf '%s\n' '# Fixture' '[Docs](Docs/README.md)' > "$tmp/README.md"
printf '%s\n' '# Fixture docs' '[Root](../README.md)' > "$tmp/Docs/README.md"
(cd "$tmp" && sh Tests/docs-links.sh)
echo "PicoKit documentation link failure fixtures passed"
