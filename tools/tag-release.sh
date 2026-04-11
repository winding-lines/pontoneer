#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Extract pontoneer version from pixi.toml
PONTONEER_VERSION=$(grep '^version = ' "$REPO_ROOT/pixi.toml" | sed 's/version = "\(.*\)"/\1/')
if [[ -z "$PONTONEER_VERSION" ]]; then
  echo "error: could not extract version from pixi.toml" >&2
  exit 1
fi

# Extract the dev date stamp from pixi.lock (e.g. dev2026040405)
MOJO_DEV=$(grep -m1 'mojo-' "$REPO_ROOT/pixi.lock" | grep -o 'dev[0-9]\+')
if [[ -z "$MOJO_DEV" ]]; then
  echo "error: could not extract mojo dev version from pixi.lock" >&2
  exit 1
fi

if [[ "$PONTONEER_VERSION" == *"$MOJO_DEV"* ]]; then
  TAG="v${PONTONEER_VERSION}"
else
  TAG="v${PONTONEER_VERSION}.${MOJO_DEV}"
fi

echo "pontoneer version : $PONTONEER_VERSION"
echo "mojo dev stamp    : $MOJO_DEV"
echo "tag               : $TAG"

if git -C "$REPO_ROOT" tag | grep -qx "$TAG"; then
  echo "error: tag $TAG already exists" >&2
  exit 1
fi

git -C "$REPO_ROOT" tag "$TAG"
echo "created tag $TAG"
git -C "$REPO_ROOT" push origin "$TAG"
