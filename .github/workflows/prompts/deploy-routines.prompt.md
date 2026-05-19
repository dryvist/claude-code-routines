# Deploy routines

Instructions for Claude when invoked by `.github/workflows/deploy-routines.yml`.

For every file matching `routines/*.prompt.md` in this checkout:

1. Read the file. Parse the YAML frontmatter for `trigger_id`, `cron`,
   `model`, and `allowed_tools`. Extract the body below the closing
   `---` of the frontmatter — call it BODY.
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
   Extract the current cloud body from
   `job_config.ccr.events[0].data.message.content`. If it equals BODY
   exactly, print `SKIP <basename> (in sync)` and move to the next
   file — do not call `update`.
4. If BODY differs, call the `RemoteTrigger` tool with `action: update`,
   the file's `trigger_id`, and this body shape:

   ```json
   {
     "job_config": {
       "ccr": {
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
           "model": "<from frontmatter>"
         }
       }
     }
   }
   ```

5. Verify the update by calling `RemoteTrigger` `action: get` for the
   same `trigger_id` and confirming the returned
   `job_config.ccr.events[0].data.message.content` equals BODY exactly.

Print one `CREATED <basename> trigger_id=<id>`, `PASS <basename>`,
`SKIP <basename> (in sync)`, or `FAIL <basename> — <reason>` line per
file. Exit non-zero if any FAIL.

## Auto-create (for cloud routines without a `trigger_id`)

A) Fetch the canonical request shape from an existing cloud routine
   instead of guessing field names. Pick any file under `routines/`
   that **does** carry a `trigger_id`, call
   `RemoteTrigger action: get` on it, and inspect the full returned
   object. That object is the authoritative schema (`name`,
   `cron_expression` or `cron`, `job_config`, etc. — whatever the
   server actually uses today).

   Build the `create` body by deep-copying that schema and then
   substituting only the per-routine fields from the new file's
   frontmatter and body: the routine name (frontmatter `name`); the
   schedule (frontmatter `cron`, written into whatever schedule field
   the canonical shape uses); `session_context.allowed_tools` and
   `session_context.model` from frontmatter; and
   `events[0].data.message.content` set to the prompt BODY. Leave
   every other field at its canonical-shape default. This keeps the
   deploy prompt a single source of truth and avoids drift if
   Anthropic adds optional fields to the API.

   Call `RemoteTrigger action: create` with the resulting body and
   extract the new `trigger_id` from the response. If the API rejects
   the shape, surface the full error in a `FAIL <basename>` line so
   a human can adjust this prompt; do not retry blindly.

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
