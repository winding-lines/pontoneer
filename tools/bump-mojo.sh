#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -eq 0 ]]; then
  echo "fetching latest mojo version from pixi search..."
  NEW_VER=$(pixi search mojo-compiler 2>/dev/null | grep '^Version' | head -1 | awk '{print $2}')
  if [[ -z "$NEW_VER" ]]; then
    echo "error: could not determine latest mojo version from pixi search" >&2
    exit 1
  fi
  echo "found: $NEW_VER"
elif [[ $# -eq 1 ]]; then
  NEW_VER="$1"
else
  echo "Usage: $0 [mojo-version]" >&2
  echo "Example: $0 0.26.3.0.dev2026041020" >&2
  echo "If no version is given, the latest is fetched via pixi search." >&2
  exit 1
fi

# Validate the version looks like a mojo nightly version
if [[ ! "$NEW_VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.dev[0-9]+$ ]]; then
  echo "error: version '$NEW_VER' does not match expected format (e.g. 0.26.3.0.dev2026041020)" >&2
  exit 1
fi

PIXI_TOML="$REPO_ROOT/pixi.toml"

# Show what will change
OLD_VER=$(grep -m1 'mojo.*==[0-9]' "$PIXI_TOML" | grep -o '[0-9][0-9.]*\.dev[0-9]*')
echo "bumping mojo: $OLD_VER -> $NEW_VER"

sed -i '' "s/==[0-9][0-9.]*\.dev[0-9]*/==${NEW_VER}/g" "$PIXI_TOML"

echo "updated $PIXI_TOML"
