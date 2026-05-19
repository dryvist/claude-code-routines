---
name: Deploy routine changes
description: >-
  Use whenever a `routines/*.prompt.md` file in this repo
  (`claude-code-routines`) is created or edited. The GHA deploy
  workflow at `.github/workflows/deploy-routines.yml` is disabled
  because its `CLAUDE_CODE_OAUTH_TOKEN` cannot reach the Anthropic
  Routines API — see the workflow header for details. Cloud-routine
  bodies are now kept in sync by Claude calling `RemoteTrigger`
  directly during the editing session. Invoke this skill at the end
  of any session that modified a routine, before reporting done.
---

# Deploy routine changes

The interactive Claude Code harness has working `RemoteTrigger`
access. This skill walks you through pushing routine-prompt changes
to the live Anthropic cloud routines. The mirrored GHA workflow is
disabled; do not try to trigger it.

## When to run

- A routine file at `routines/*.prompt.md` was created or modified
  during this session (the `.claude/settings.json` hook should have
  reminded you).
- The user merged a PR that touched a routine file and you are
  picking up afterward.
- Drift suspected on a routine even without a recent edit.

## Step 1 — Identify routines to sync

```bash
git diff --name-only origin/main...HEAD -- 'routines/*.prompt.md' 2>/dev/null
git diff --name-only HEAD -- 'routines/*.prompt.md'
```

Union the two lists. If empty and no drift is suspected, stop here.

If working from a post-merge session (no diff against `origin/main`),
fall back to syncing every cloud routine in the repo:

```bash
ls routines/*.prompt.md
```

## Step 2 — Per file: parse the frontmatter

Read the file. The YAML frontmatter is everything between the first
two `---` lines. Extract:

- `name`
- `trigger_id` (may be absent)
- `cron` (may be absent)
- `model`
- `allowed_tools`

The prompt BODY is everything after the closing `---`.

## Step 3 — Decide what to do per file

| `trigger_id` | `cron` | Action |
| --- | --- | --- |
| absent | absent | SKIP — GHA-managed (see Note A) |
| absent | present | CREATE — follow Step 4 |
| present | (any) | UPDATE-IF-DRIFTED — follow Step 5 |

Note A: prompts without `trigger_id` and without `cron` are
GHA-managed (e.g. `issue-solver.prompt.md`, driven by
`.github/workflows/issue-solver.yml`). Do not touch them from
this skill.

## Step 4 — Create a new cloud routine

The Routines API requires `job_config.ccr.environment_id` and a few
other top-level fields that are easy to drop. The reliable path:
**fetch the canonical shape from an existing routine first, then
substitute only the per-routine fields.**

1. Pick any sibling file with a `trigger_id` (e.g.
   `routines/daily-polish.prompt.md`). Call:

   ```text
   RemoteTrigger action=get trigger_id=<sibling-trigger-id>
   ```

2. From the response, build the create body by **deep-copying the
   entire `job_config` and every top-level field**, then substituting
   only:

   - top-level `name` ← new file's frontmatter `name`
   - top-level `cron_expression` ← new file's frontmatter `cron`
     (note the rename: API field is `cron_expression`, frontmatter
     field is `cron`)
   - `job_config.ccr.session_context.allowed_tools` ← frontmatter
     `allowed_tools`
   - `job_config.ccr.session_context.model` ← frontmatter `model`
   - `job_config.ccr.events[0].data.message.content` ← the prompt
     BODY

3. **Preserve verbatim** from the canonical response — do NOT drop:
   `job_config.ccr.environment_id`, `mcp_connections`,
   `persist_session`, and any other top-level fields. Dropping
   `environment_id` produces HTTP 400 `ccr.environment_id required`.

4. Call `RemoteTrigger action=create` with the resulting body.
   Extract `id` from the response — that's the new `trigger_id`.

5. Edit the routine file: insert `trigger_id: <new-id>` into the
   frontmatter immediately after the `name:` line. Don't reorder
   anything else.

6. Commit and push the trigger_id back-commit via a normal PR
   (worktree → branch → commit → push → `gh pr create`). Keep the
   diff to the one frontmatter line — a small follow-up PR is the
   right shape. Commit message:
   `chore(routines): set trigger_id for <basename>`.

## Step 5 — Update if the cloud body drifted

1. Call `RemoteTrigger action=get trigger_id=<file's trigger_id>`.

2. Extract `job_config.ccr.events[0].data.message.content` from the
   response — this is CLOUD_BODY. Read the file's prompt BODY.

3. If they match exactly: report `SKIP <basename> (in sync)` and
   move on.

4. If they differ: build the update body by deep-copying the get
   response and substituting only:

   - `job_config.ccr.events[0].data.message.content` ← file BODY
   - `job_config.ccr.session_context.allowed_tools` ← frontmatter
     `allowed_tools`
   - `job_config.ccr.session_context.model` ← frontmatter `model`
   - top-level `cron_expression` ← frontmatter `cron`

   Preserve everything else verbatim — same rule as Step 4.

5. Call `RemoteTrigger action=update trigger_id=<id>` with the
   resulting body.

6. Verify: re-issue `RemoteTrigger action=get`. The content should
   now equal file BODY. If not, surface the discrepancy in the
   report and stop — do not retry blindly.

## Step 6 — Report

At the end of the session, emit a one-line-per-file summary so the
user can confirm the cloud is in sync:

```text
Cloud routine sync:
  SKIP   issue-solver         (no trigger_id — managed by GHA)
  UPDATED sentinel            (placeholder → real body)
  SKIP   daily-polish         (in sync)
  CREATED <new-name>          (trigger_id=<id>, PR #<n> opened)
  FAIL   <name>               (<reason>)
```

## Hard rules

- **Never** call `gh workflow run deploy-routines.yml`. The workflow
  is disabled; running it produces no-op success and confuses the
  signal.
- **Never** modify `routines/issue-solver.prompt.md` and expect this
  skill to sync it. Issue Solver is GHA-managed; its body lives in
  the repo only.
- **Never** trust an `is_error: false` from the agent wrapper as
  evidence that a RemoteTrigger call succeeded. Always verify with
  a follow-up `RemoteTrigger get`.
- **Never** commit a real `trigger_id: trig_TBD` placeholder. Either
  the trigger_id is real or the field is absent.

## Failure modes you might hit

- `Unable to resolve organization UUID` — this is the failure that
  killed the GHA workflow. If your session's `RemoteTrigger` hits
  it too, the harness's auth has changed; surface to the user and
  stop. Don't loop.
- API rejects create with a missing-required-field error — you
  dropped something from the canonical shape. Re-fetch a sibling's
  get response and audit your substitution.
- The cloud `mcp_connections` for a new routine differ from the
  sibling's — the operator may need to configure MCP wiring in the
  cloud UI. Note in the report; don't try to set MCP from this skill.

## Background — why this is a skill, not a workflow

See the header of `.github/workflows/deploy-routines.yml`. Short
version: claude.ai's OAuth token-issuance flow does not bind an org
UUID into tokens used by `claude-code-action@v1`, but the
RemoteTrigger API requires one. The interactive Claude Code harness
authenticates differently and works fine. Until the upstream token
flow is fixed, this skill is the deploy path.
