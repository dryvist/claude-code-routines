Cross-run memory lives in one **private** GitHub Gist named `<routine>-state`. Standard schema skeleton (v2):

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

Routine-specific fields (cooldowns, caches, ignore lists) extend this skeleton — the schema shown in this routine's state section is authoritative for those fields and, for legacy routines, may replace the skeleton outright.

- **Fail open.** If the gist fetch fails (404, network error, parse error, non-JSON): proceed with empty in-memory state, set `gist_fallback=true` for the Slack output, and continue. Never crash on missing or corrupt state.
- **Retention is per-field, not blanket.** `run_log` trimmed to 90 days (archive overflow to a sibling gist `<routine>-state-archive`); rejection/ignore memory (e.g. `closed_pairs`, `codeql_ignore`) retained indefinitely — it must outlive trim windows; cooldowns trimmed once expired. Hard cap 1 MB per gist.
- **Never write secrets**, raw alert payloads, full PR diffs, or repo file contents to a state gist. `run_log[].reason` is bounded to 200 chars after redaction.
- **Prompt fingerprint.** Each run computes `sha256` of this prompt body and overwrites the gist's `prompt_sha256` (only the most recent fingerprint is kept). A mismatch against the prompt file at HEAD of `main` in the source repo indicates a stale or out-of-band-mutated cloud deployment.
- **Create-if-missing without touching the local filesystem** (substitute this routine's initial schema, stringified):

  ```bash
  jq -n '{files:{"state.json":{content:"<initial schema JSON>"}},public:false,description:"<routine>-state"}' \
    | gh api gists -X POST --input -
  ```

  Update via `gh api gists/<id> -X PATCH --input -` with a jq-built payload — same nested-JSON rule as commits: never flat `-f` keys.
