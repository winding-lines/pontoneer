#!/usr/bin/env bash
set -euo pipefail

FORCE=0
while getopts "f" opt; do
  case "$opt" in
    f) FORCE=1 ;;
    *) echo "usage: $(basename "$0") [-f]" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Extract pontoneer version from pixi.toml
PONTONEER_VERSION=$(grep '^version = ' "$REPO_ROOT/pixi.toml" | sed 's/version = "\(.*\)"/\1/')
if [[ -z "$PONTONEER_VERSION" ]]; then
  echo "error: could not extract version from pixi.toml" >&2
  exit 1
fi

# Extract the full mojo version from pixi.lock (e.g. 1.0.0b1.dev2026042405)
MOJO_VERSION=$(grep -m1 'mojo-compiler-' "$REPO_ROOT/pixi.lock" \
  | grep -oE 'mojo-compiler-[0-9][0-9a-z.]*\.dev[0-9]+' \
  | sed 's/^mojo-compiler-//')
if [[ -z "$MOJO_VERSION" ]]; then
  echo "error: could not extract mojo version from pixi.lock" >&2
  exit 1
fi

# Strip any .devXXX suffix from pontoneer version so the tag base is clean
PONTONEER_BASE="${PONTONEER_VERSION%.dev[0-9]*}"

TAG="v${PONTONEER_BASE}+mojo${MOJO_VERSION}"

echo "pontoneer version : $PONTONEER_VERSION"
echo "mojo version      : $MOJO_VERSION"
echo "tag               : $TAG"

if [[ "$FORCE" -eq 0 ]] && git -C "$REPO_ROOT" tag | grep -qx "$TAG"; then
  echo "error: tag $TAG already exists (use -f to overwrite)" >&2
  exit 1
fi

FORCE_FLAG=$([[ "$FORCE" -eq 1 ]] && echo "--force" || echo "")
git -C "$REPO_ROOT" tag $FORCE_FLAG "$TAG"
echo "created tag $TAG"
git -C "$REPO_ROOT" push origin $FORCE_FLAG "$TAG"
