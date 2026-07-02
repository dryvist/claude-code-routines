**Connectivity preflight (load-bearing).** Immediately after the paused check and
**before any GitHub enumeration or state I/O**, verify the token and egress are
live. On ANY failure, emit the `🔴 FATAL` template below and **exit** — never
proceed, never emit a "no findings / nothing to do" success message. An empty
result *after* a passing preflight means a genuinely quiet estate; an empty result
must NEVER be produced by an unverified failure.

```bash
# 1) Auth canary — a real 401 is a token problem, distinct from egress.
if ! WHOAMI=$(gh api user --jq .login 2>/tmp/pf.err); then
  ERR=$(head -c 200 /tmp/pf.err)
  case "$ERR" in
    *401*|*"Bad credentials"*)                   CAUSE="GH_TOKEN rejected (HTTP 401) — rotate/re-paste the PAT";;
    *"not permitted through this proxy"*|*403*)  CAUSE="GitHub egress blocked by proxy (HTTP 403)";;
    *)                                           CAUSE="GitHub API unreachable — $ERR";;
  esac
  # emit the 🔴 FATAL template with CAUSE, then EXIT
fi
# 2) REST-egress canary — a 502 here means blind, not quiet.
if ! gh api rate_limit >/dev/null 2>/tmp/pf.err; then
  CAUSE="REST egress down (e.g. HTTP 502) — $(head -c 200 /tmp/pf.err)"
  # emit the 🔴 FATAL template with CAUSE, then EXIT
fi
```

FATAL Slack template (`🔴` is reserved for this; `🛑` is the paused kill-switch):

```text
🔴 <Routine> — <date> — FATAL: <CAUSE>
No repos were scanned; no PRs/issues/labels/merges were created; state not written.
Action: verify GH_TOKEN and the routine env egress allowlist (api.github.com).
See docs/CLOUD_ROUTINES_AUTH.md → Outage recovery.
```

This preflight is separate from `state_fallback` (state-file partial): a blocked or
unreachable *primary* GitHub API is FATAL here; a *state-file* miss after this passes
is only a soft memory-degradation banner.
