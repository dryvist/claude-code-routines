# Deploy routines — DEPRECATED 2026-05-19

> **This prompt is not currently used.** The workflow that invokes it
> (`.github/workflows/deploy-routines.yml`) has had its triggers
> removed because the `CLAUDE_CODE_OAUTH_TOKEN` injected into the
> action does not have the org binding the Anthropic Routines API
> needs (`Unable to resolve organization UUID` on every call,
> verified across two token rotations on 2026-05-19).
>
> The active deploy procedure is at
> `.claude/skills/deploy-routine-changes/SKILL.md` — Claude runs it
> in an interactive session in this repo, where the harness has
> working RemoteTrigger access. This file is kept as historical
> reference for the auto-deploy design (which would still be correct
> if the OAuth token issue is fixed upstream).

Instructions for Claude when invoked by `.github/workflows/deploy-routines.yml`.

For every file matching `routines/*.prompt.md` in this checkout:

1. Read the file. Parse the YAML frontmatter for `trigger_id`, `cron`,
   `model` (may be absent → use `$MODEL` default), `allowed_tools`, and
   `autofix` (absent → `false`). Extract the body below the closing
   `---` of the frontmatter — call it BODY. Read the pinned cloud
   environment id and default model once, and set
   `job_config.ccr.environment_id` and
   `job_config.ccr.session_context.model` accordingly on every
   create/update:

   ```bash
   ENVIRONMENT_ID=$(grep -m1 '^ENVIRONMENT_ID=' \
     routines/_common/deploy.config | cut -d= -f2 | tr -d '\r')
   MODEL=$(grep -m1 '^CLAUDE_SONNET_MODEL_ID=' \
     routines/_common/deploy.config | cut -d= -f2 | tr -d '\r')
   ```

2. **If the frontmatter has no `trigger_id` field**, distinguish two
   cases using the `cron` field:
   - `cron` is **absent** → the file is a GitHub-Actions-managed prompt
     (e.g. `issue-solver.prompt.md`, which is driven by
     `.github/workflows/issue-solver.yml`, not the cloud). Print
     `SKIP <basename> (no trigger_id — managed by GHA)` and move on.
   - `cron` is **present** → the routine is a cloud routine that has
     not yet been registered. Auto-register it (see the "Auto-create"
     section below). On success, continue to step 3 with the
     freshly-issued `trigger_id`. On failure (HTTP error from
     `RemoteTrigger create`, missing required field, etc.), print
     `FAIL <basename> — auto-create failed: <reason>` and move on.
3. Call `RemoteTrigger` with `action: get` for the `trigger_id`.
   Compare three things to the desired state: the cloud body
   (`job_config.ccr.events[0].data.message.content`) vs BODY, the cloud
   `job_config.ccr.environment_id` vs `$ENVIRONMENT_ID`, and
   `job_config.ccr.session_context.autofix_on_pr_create` vs frontmatter
   `autofix` (treat absent/null on either side as `false`). If ALL THREE
   match, print `SKIP <basename> (in sync)` and move to the next file —
   do not call `update`.
4. If any of the three differ, call `RemoteTrigger` with
   `action: update`, the file's `trigger_id`, and the COMPLETE `ccr`
   below. `update` REPLACES `job_config.ccr` wholesale — a partial
   `ccr` (e.g. omitting `events`) WIPES the prompt body, so always
   send `environment_id` + `events` + `session_context` together:

   ```json
   {
     "job_config": {
       "ccr": {
         "environment_id": "<$ENVIRONMENT_ID>",
         "events": [{
           "data": {
             "message": {
               "content": "<BODY>",
               "role": "user"
             },
             "type": "user"
           }
         }],
         "session_context": {
           "allowed_tools": "<from frontmatter>",
           "model": "<frontmatter model, or $MODEL default>",
           "autofix_on_pr_create": <frontmatter autofix, default false>
         }
       }
     }
   }
   ```

5. Verify the update by calling `RemoteTrigger` `action: get` for the
   same `trigger_id` and confirming: the returned
   `job_config.ccr.events[0].data.message.content` equals BODY exactly,
   `environment_id` equals `$ENVIRONMENT_ID`, and
   `autofix_on_pr_create` equals the frontmatter `autofix`.

Print one `CREATED <basename> trigger_id=<id>`, `PASS <basename>`,
`SKIP <basename> (in sync)`, or `FAIL <basename> — <reason>` line per
file. Exit non-zero if any FAIL.

## Auto-create (for cloud routines without a `trigger_id`)

A) Fetch the canonical request shape from an existing cloud routine
   instead of guessing field names. Pick any file under `routines/`
   that **does** carry a `trigger_id`, call
   `RemoteTrigger action: get` on it, and inspect the full returned
   object. That object is the authoritative schema.

   Build the `create` body by **deep-copying the entire
   `job_config` and every top-level field** from the canonical
   response, then substituting only these per-routine fields:
   top-level `name` ← frontmatter `name`; top-level `cron_expression`
   ← frontmatter `cron` (note the rename: the API field is
   `cron_expression`, the frontmatter field is `cron`);
   `job_config.ccr.session_context.allowed_tools` ← frontmatter
   `allowed_tools`; `job_config.ccr.session_context.model` ←
   frontmatter `model` if present, else `$MODEL`;
   `job_config.ccr.session_context.autofix_on_pr_create` ← frontmatter
   `autofix` (absent → `false`); `job_config.ccr.environment_id` ←
   `$ENVIRONMENT_ID`; `job_config.ccr.events[0].data.message.content`
   ← the prompt BODY.

   **Preserve verbatim from the canonical response — do not drop
   any of these:** `mcp_connections` (otherwise the new routine has no
   Slack wiring), `persist_session`, and any other top-level field the
   canonical shape contains that the substitution list above does not
   override. `environment_id` must be present — it is set from
   `$ENVIRONMENT_ID` above (the cloud rejects creates without it:
   HTTP 400 `ccr.environment_id required`).

   Treat the canonical response as the single source of truth for
   field names and required values. The substitution list is what
   the new routine differs in; everything else stays.

   Call `RemoteTrigger action: create` with the resulting body and
   extract the new `trigger_id` from the response. If the API
   rejects the shape, surface the full error in a `FAIL <basename>`
   line so a human can adjust this prompt; do not retry blindly.

B) Once the new `trigger_id` is in hand, write it back into the
   prompt file's YAML frontmatter via the GitHub Contents API so
   future deploy runs hit the standard `update` path.

   1. Read the file's current Contents-API SHA on `main`:

      ```bash
      gh api repos/${GITHUB_REPOSITORY}/contents/routines/<basename>.prompt.md \
        --jq '.sha'
      ```

   2. With the `Edit` tool, insert `trigger_id: <new-id>` into the
      YAML frontmatter immediately after the `name:` line of the
      checked-out file. Stage the resulting full file content into
      `/tmp/scratch.<basename>.md`.

   3. PUT the new content via the Contents API. The `committer`
      object MUST be nested — build the payload with `jq -n` and
      pipe via `--input -` (flat `-f committer.name=...` is dropped
      by the API). Use the GitHub Actions bot identity:

      ```bash
      REPO_PATH="routines/<basename>.prompt.md"
      jq -n \
        --arg msg "chore: set trigger_id for <basename> [auto-deploy]" \
        --arg content "$(base64 -w0 < /tmp/scratch.<basename>.md)" \
        --arg branch "main" \
        --arg sha "<file-sha-from-step-1>" \
        --arg cname "github-actions[bot]" \
        --arg cemail "41898282+github-actions[bot]@users.noreply.github.com" \
        '{message:$msg, content:$content, branch:$branch, sha:$sha,
          committer:{name:$cname, email:$cemail}}' \
      | gh api "repos/${GITHUB_REPOSITORY}/contents/${REPO_PATH}" \
          -X PUT --input -
      ```

C) Continue to step 3 of the main loop using the new `trigger_id`.
   The first `get` will now succeed and the immediately-following
   verification will print `SKIP <basename> (in sync)` because the
   cloud body already matches BODY (it was just used to create the
   routine).

Note on side-effects: the back-commit lands directly on `main` and
will be picked up by the next deploy run. That is intentional — the
routine is now self-bootstrapped and any subsequent prompt-only edit
goes through the standard `update` path. The commit is signed by
GitHub web-flow (Contents API + `GITHUB_TOKEN`) and attributed to
`github-actions[bot]`.

Beyond the trigger_id back-commit, do not modify this repository.
