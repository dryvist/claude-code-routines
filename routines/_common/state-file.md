Cross-run memory lives as one **JSON file per routine** in the private repo
`$STATE_REPO` (in the `$GH_OWNER` org), on the **`data` branch**, at
`state/<routine>.json`. The shared PR budget is `pr-budget.json` at the root of
the same branch. **Gists are NOT used** — the cloud egress proxy blocks gist
writes (`"Gist writes are not permitted through this proxy"`, HTTP 403). **State
lives on `data`, not `main`,** because the org ruleset makes `main` require a
pull request for every change — impossible for per-run writes; the `data` branch
only requires verified signatures, which the Contents API's web-flow signing
already provides. All state I/O goes through the GitHub Contents API against
`data`. Standard schema skeleton (v2):

```json
{
  "schema_version": 2,
  "prompt_sha256": "abc123…",
  "run_log": [
    {"ts":"2026-05-25T14:00:00Z","repo":"<owner>/<repo>",
     "action":"<verb>","resource_id":"<url>","reason":""}
  ]
}
```

Routine-specific fields (cooldowns, caches, ignore lists) extend this skeleton —
the schema shown in this routine's state section is authoritative for those
fields.

**Read — capture the blob `sha` for write-back, distinguish 404 from transient:**

```bash
STATE_PATH="state/<routine>.json"
if gh api "repos/$STATE_REPO/contents/$STATE_PATH?ref=data" >/tmp/sr.json 2>/tmp/sr.err; then
  STATE_SHA=$(jq -r '.sha' /tmp/sr.json)
  STATE=$(jq -r '.content' /tmp/sr.json | base64 -d)
elif grep -qiE '404|not found' /tmp/sr.err; then
  STATE_SHA=""; STATE='<initial schema JSON>'          # first run — safe to create
else
  STATE_SHA=""; STATE='<initial schema JSON>'          # transient error — read-only this run
  STATE_WRITE_DISABLED=1; state_fallback=true
fi
```

**Write — optimistic lock; retry once on 409 (stale sha):**

```bash
put_state() {  # $1 = full new state JSON
  jq -n \
    --arg content "$(printf '%s' "$1" | base64 -w0)" \
    --arg branch  "data" \
    --arg cname   "$GIT_COMMITTER_NAME" \
    --arg cemail  "$GIT_COMMITTER_EMAIL" \
    --arg msg     "chore(state): <routine> run" \
    --arg sha     "$STATE_SHA" \
    '{message:$msg, content:$content, branch:$branch,
      committer:{name:$cname, email:$cemail}}
     + (if $sha == "" then {} else {sha:$sha} end)' \
  | gh api "repos/$STATE_REPO/contents/$STATE_PATH" -X PUT --input -
}
```

- On HTTP **409** (someone else wrote since your read): re-read the file, re-apply
  your delta to the fresh content, and PUT again. Do this at most twice; if it
  still conflicts, emit a one-line Slack warning and continue (best-effort).
- If `STATE_WRITE_DISABLED` is set (transient read error above), do NOT write this
  run — you would clobber history with empty state.

**Fail open, scoped.** A *state-file* miss is a soft degradation of **memory
only**: 404 → create-if-missing; network/parse error → empty in-memory state with
`state_fallback=true` (prepend the one-line banner to Slack, per the Slack-output
partial). This is NOT a primary-egress failure — the connectivity preflight (Hard
Rules) has already turned a blocked/unreachable GitHub API into a `🔴 FATAL` exit
long before this point. Never let a state miss masquerade as "nothing to do", and
never let an egress outage masquerade as a state miss.

**Retention per-field, not blanket.** `run_log` trimmed to 90 days (overflow →
`state/<routine>-archive.json`); rejection/ignore memory (`closed_pairs`,
`codeql_ignore`) retained indefinitely — it must outlive trim windows; cooldowns
trimmed once expired. Hard cap ~1 MB per file.

**Never write secrets**, raw alert payloads, full PR diffs, or repo file contents
to a state file. `run_log[].reason` is bounded to 200 chars after redaction.

**Shared PR budget** — `pr-budget.json` at the `$STATE_REPO` root, schema
`{ "<YYYY-MM-DD>": {"<owner>/<repo>": <count>} }`. Read the day's counter (same
read + `sha` pattern as above); skip the repo if it is already at the estate-wide
soft cap (2 PRs per repo per UTC day across all routines); otherwise increment and
write back (same optimistic-lock PUT). If `pr-budget.json` is missing or corrupt:
fail open (proceed with this routine's own per-run cap) AND emit a Slack warning.

**Prompt fingerprint (written, not consumed).** Each run overwrites
`prompt_sha256` with `sha256` of this prompt body. No routine currently reads it
back — the historical "Sentinel cross-checks the fingerprint" mechanism was never
implemented and Sentinel is retired. It is kept as a cheap breadcrumb for a future
out-of-band monitor; do not rely on it for drift detection today.
