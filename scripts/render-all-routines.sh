#!/usr/bin/env bash
# Render every routines/*.prompt.md into an output directory (default
# /tmp/rendered). Exits nonzero if any render fails.
set -euo pipefail

out_dir="${1:-/tmp/rendered}"
mkdir -p "$out_dir"

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(dirname "$script_dir")"

for f in "$repo_root"/routines/*.prompt.md; do
  bash "$script_dir/render-routine.sh" "$f" > "$out_dir/$(basename "$f")"
  echo "rendered $(basename "$f")"
done
