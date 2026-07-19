#!/usr/bin/env bash
# Render every centrally managed routine prompt into an output directory.
set -euo pipefail

out_dir="${1:-/tmp/rendered}"
mkdir -p "$out_dir"

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(dirname "$script_dir")"
catalog_root="${AI_LLM_PROMPTS_DIR:-$repo_root/vendor/ai-llm-prompts}"

for prompt in "$catalog_root"/automation/routine-*.md; do
  basename="$(basename "$prompt")"
  case "$basename" in
    routine-fragment-*|routine-deploy-reference.md) continue ;;
  esac
  name="${basename#routine-}"
  name="${name%.md}"
  bash "$script_dir/render-routine.sh" "$name" > "$out_dir/$name.prompt.md"
  echo "rendered $name.prompt.md"
done
