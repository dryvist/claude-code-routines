#!/usr/bin/env bash
# Render one centrally managed routine prompt by stripping OKF frontmatter and
# expanding flattened routine-fragment include markers.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(dirname "$script_dir")"
catalog_root="${AI_LLM_PROMPTS_DIR:-$repo_root/vendor/ai-llm-prompts}"

routine="${1:-}"
if [ -z "$routine" ]; then
  IFS= read -r routine
fi

if [ -f "$routine" ]; then
  prompt_file="$routine"
else
  name="$(basename "$routine")"
  name="${name#routine-}"
  name="${name%.prompt.md}"
  name="${name%.md}"
  prompt_file="$catalog_root/automation/routine-$name.md"
fi

if [ ! -f "$prompt_file" ]; then
  echo "render-routine: no catalog prompt for $routine: $prompt_file" >&2
  exit 1
fi

strip_frontmatter() {
  awk '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { in_frontmatter = 0; next }
    !in_frontmatter { print }
    END { if (in_frontmatter) exit 1 }
  ' "$1"
}

base_dir="$(dirname "$prompt_file")"
marker_re='^<!-- include: (routine-fragment-[A-Za-z0-9._-]+\.md) -->$'
rendered_source="$(strip_frontmatter "$prompt_file")"

while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ $marker_re ]]; then
    partial="$base_dir/${BASH_REMATCH[1]}"
    if [ ! -f "$partial" ]; then
      echo "render-routine: unresolvable include in $prompt_file: $line" >&2
      exit 1
    fi
    if strip_frontmatter "$partial" | grep -Eq '^<!-- include: '; then
      echo "render-routine: nested include in partial $partial (forbidden)" >&2
      exit 1
    fi
    strip_frontmatter "$partial"
  else
    printf '%s\n' "$line"
  fi
done <<< "$rendered_source"
