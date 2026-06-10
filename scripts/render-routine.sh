#!/usr/bin/env bash
# Render a routine prompt by expanding `<!-- include: _common/<name>.md -->`
# markers with the referenced partial's content. The rendered output (stdout)
# is what gets deployed; the repo file is the DRY source form.
#
# Usage: render-routine.sh <routines/NAME.prompt.md>
#        echo routines/NAME.prompt.md | render-routine.sh
#
# Exits nonzero on: missing/unreadable input, an unresolvable include, or a
# _common/ partial that itself contains an include marker (nesting forbidden).
set -euo pipefail

routine="${1:-}"
if [ -z "$routine" ]; then
  IFS= read -r routine
fi
if [ ! -f "$routine" ]; then
  echo "render-routine: no such file: $routine" >&2
  exit 1
fi

base_dir="$(dirname "$routine")"
marker_re='^<!-- include: (_common/[A-Za-z0-9._-]+\.md) -->$'

while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" =~ $marker_re ]]; then
    partial="$base_dir/${BASH_REMATCH[1]}"
    if [ ! -f "$partial" ]; then
      echo "render-routine: unresolvable include in $routine: $line" >&2
      exit 1
    fi
    if grep -Eq '^<!-- include: ' "$partial"; then
      echo "render-routine: nested include in partial $partial (forbidden)" >&2
      exit 1
    fi
    cat "$partial"
  else
    printf '%s\n' "$line"
  fi
done < "$routine"
