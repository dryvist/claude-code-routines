#!/bin/bash
# Linear GraphQL API wrapper.
#
# Hardcodes the endpoint and authentication so the prompt's tool allowlist
# can grant Linear access without also granting "make any HTTPS request"
# via curl. See refactor(solver) PR #31 — addressing the security review
# finding about `Bash(curl:*)` being too permissive.
#
# Usage: pass a GraphQL request body (as JSON `{query, variables}`) on
# stdin, get the response on stdout. Errors and diagnostics go to stderr.
#
#   echo '{"query":"query { viewer { id } }"}' | scripts/linear-query.sh
#
# Required env: LINEAR_API_KEY (Personal API Key scoped to JAC team).
# Exit codes: 0 on success, 1 if LINEAR_API_KEY missing, 2 on curl failure.

set -euo pipefail

if [ -z "${LINEAR_API_KEY:-}" ]; then
  echo '{"errors":[{"message":"LINEAR_API_KEY env var not set"}]}' >&2
  exit 1
fi

# `exec` so curl's exit code becomes the script's exit code.
# `-sS` = silent except errors. `--fail-with-body` = non-zero exit on HTTP
# 4xx/5xx but still emit the body so callers can parse the error.
exec curl -sS --fail-with-body \
  -X POST "https://api.linear.app/graphql" \
  -H "Authorization: Bearer ${LINEAR_API_KEY}" \
  -H "Content-Type: application/json" \
  --data @-
