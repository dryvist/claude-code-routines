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
git diff --name-only origin/main...HEAD -- 'routines/' 2>/dev/null
git diff --name-only HEAD -- 'routines/'
```

Union the two lists. If a `routines/_common/*.md` partial appears,
expand it to every `routines/*.prompt.md` file containing an include
marker for it (`grep -l 'include: _common/<name>.md' routines/*.prompt.md`).
If the union is empty and no drift is suspected, stop here.

If working from a post-merge session (no diff against `origin/main`),
fall back to syncing every cloud routine in the repo:

```bash
ls routines/*.prompt.md
```

## Step 2 — Per file: render, then parse the frontmatter

Routine files are the DRY source form: they contain
`<!-- include: _common/<name>.md -->` markers that reference shared
partials in `routines/_common/`. The cloud routine must receive the
RENDERED prompt — never the raw file with markers in it.

Render first:

```bash
scripts/render-routine.sh routines/<basename>.prompt.md > /tmp/<basename>.rendered.md
```

If the script exits nonzero (unresolvable include, nested include in a
partial), STOP for this file — report `FAIL <basename> (render error)`
and do NOT deploy it. A render failure is never deployable.

From the RENDERED output: the YAML frontmatter is everything between
the first two `---` lines. Extract:

- `name`
- `trigger_id` (may be absent)
- `cron` (may be absent)
- `model`
- `allowed_tools`
- `autofix` (may be absent → treat as `false`)

The prompt BODY is everything after the closing `---` of the RENDERED
output. All `update`/`create` content below means this rendered BODY.

Also read the single pinned cloud environment id once per run — the
repo, not the cloud UI, owns which environment each routine runs in:

```bash
ENVIRONMENT_ID=$(grep -m1 '^ENVIRONMENT_ID=' routines/_common/deploy.config | cut -d= -f2 | tr -d '\r')
```

Every create/update below sets `job_config.ccr.environment_id` to
`$ENVIRONMENT_ID`. The environment's secrets (`GH_OWNER`, `GH_TOKEN`)
live only in the cloud — this pins WHICH environment, not what's in it.

Note: editing a partial in `routines/_common/` changes the rendered
body of EVERY routine that includes it. If a `_common/*.md` file was
modified this session, treat all cloud routines as candidates and let
the Step 5 drift check sort out which ones actually changed.

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
   `routines/docs-polish.prompt.md`). Call:

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
   - `job_config.ccr.session_context.autofix_on_pr_create` ←
     frontmatter `autofix` (absent → `false`)
   - `job_config.ccr.environment_id` ← `$ENVIRONMENT_ID` from
     `routines/_common/deploy.config` (Step 2)
   - `job_config.ccr.events[0].data.message.content` ← the RENDERED
     prompt BODY (Step 2)

3. **Preserve verbatim** from the canonical response — do NOT drop:
   `mcp_connections`, `persist_session`, and any other top-level
   fields. `environment_id` must be present (set it from
   `$ENVIRONMENT_ID` per the substitution above — the cloud rejects
   creates without it: HTTP 400 `ccr.environment_id required`).
   Also keep the existing nesting under
   `job_config.ccr.events[0].data` — in particular `type: "user"`
   sits *inside* `data` as a sibling of `message`, not above it.
   If you re-shape by hand and accidentally flatten this, the API
   will reject it.

4. Call `RemoteTrigger action=create` with the resulting body.
   Extract `id` from the response — that's the new `trigger_id`.

5. Edit the routine file: insert `trigger_id: <new-id>` into the
   frontmatter immediately after the `name:` line. Don't reorder
   anything else.

6. Commit and push the trigger_id back-commit via the normal
   local git flow (worktree → branch → commit → push →
   `gh pr create`). Keep the diff to the one frontmatter line — a
   small follow-up PR is the right shape. Commit message:
   `chore(routines): set trigger_id for <basename>`.

   *Why local git here rather than the Contents API?* The Hard
   Rules in `CLAUDE.md` about Contents-API-only commits apply to
   the **cloud-routine sandbox**, where there is no signing
   identity. This skill runs
   in an **interactive Claude Code session on the user's Mac**,
   which has GPG signing configured via nix-home. Local commits
   from this context are signed and pass `required_signatures`
   rulesets exactly the same way the user's own commits do. Don't
   route this through the Contents API just because reviewers see
   "no `git commit`" in CLAUDE.md and assume it applies
   universally — it does not.

## Step 5 — Update if the cloud body drifted

1. Call `RemoteTrigger action=get trigger_id=<file's trigger_id>`.

2. From the response capture: CLOUD_BODY
   (`job_config.ccr.events[0].data.message.content`),
   `job_config.ccr.environment_id`, and
   `job_config.ccr.session_context.autofix_on_pr_create`. Take the
   RENDERED BODY, `$ENVIRONMENT_ID`, and the frontmatter `autofix`
   from Step 2. Normalize both `autofix_on_pr_create` and frontmatter
   `autofix` to `false` when absent or `null` before comparing — older
   routines may lack the field and the API may omit falsey values.

3. **In sync only if ALL THREE match**: CLOUD_BODY == RENDERED BODY,
   `environment_id` == `$ENVIRONMENT_ID`, and `autofix_on_pr_create`
   == frontmatter `autofix`. If so, report `SKIP <basename> (in sync)`
   and move on. (Body-only checks let an out-of-band env or autofix
   drift slip through — that is exactly the bug this guards against.)

4. If any differ: show the operator the body diff (write CLOUD_BODY
   and RENDERED BODY to temp files, `diff -u`) and note any env /
   autofix change. Then build the update body by deep-copying the get
   response and substituting only:

   - `job_config.ccr.events[0].data.message.content` ← RENDERED BODY
   - `job_config.ccr.session_context.allowed_tools` ← frontmatter
     `allowed_tools`
   - `job_config.ccr.session_context.model` ← frontmatter `model`
   - `job_config.ccr.session_context.autofix_on_pr_create` ←
     frontmatter `autofix` (absent → `false`)
   - `job_config.ccr.environment_id` ← `$ENVIRONMENT_ID`
   - top-level `cron_expression` ← frontmatter `cron`

   If the frontmatter `name` differs from the trigger's top-level
   `name` (a rename), also substitute:

   - top-level `name` ← frontmatter `name`

   Preserve everything else verbatim — same rule as Step 4,
   including the `type: "user"` nested inside
   `job_config.ccr.events[0].data` next to `message`.

   **Critical:** `update` REPLACES `job_config.ccr` wholesale. The
   deep-copy above is what makes this safe — if you send a partial
   `ccr` (e.g. only `environment_id`), the API drops `events` and the
   prompt body is WIPED. Always send the COMPLETE `ccr`
   (`environment_id` + `events` + `session_context`).

5. Call `RemoteTrigger action=update trigger_id=<id>` with the
   resulting body.

6. Verify: re-issue `RemoteTrigger action=get`. Confirm the returned
   content equals RENDERED BODY (exact — sha or `diff`),
   `environment_id` == `$ENVIRONMENT_ID`, and `autofix_on_pr_create`
   == frontmatter `autofix`. If any check fails, surface it in the
   report and stop — do not retry blindly.

## Step 5b — Disabling a retired or merged-away trigger

When a routine is retired or merged into another, its trigger is
DISABLED — never deleted (trigger_ids stay in the AGENTS.md ledger)
and never reused. The trigger object has a top-level `enabled`
boolean, and `update` is a partial update at the TOP level (partial
`job_config.ccr` is what wipes bodies — top-level partials are safe):

```text
RemoteTrigger action=update trigger_id=<id> body={"enabled": false}
RemoteTrigger action=get trigger_id=<id>     # verify enabled == false
```

Pair a merge-away disable with the absorbing routine's update in the
same sitting so the coverage gap is minutes. `enabled: false` is also
the per-routine pause/rollback lever during staged deploys.

## Step 6 — Report

At the end of the session, emit a one-line-per-file summary so the
user can confirm the cloud is in sync:

```text
Cloud routine sync:
  SKIP    issue-solver        (no trigger_id — managed by GHA)
  UPDATED estate-briefing     (body + name)
  SKIP    docs-polish         (in sync)
  DISABLED <old-name>         (merged into <new-name>)
  CREATED <new-name>          (trigger_id=<id>, PR #<n> opened)
  FAIL    <name>              (<reason>)
```

## Hard rules

- **Never** send a raw `routines/*.prompt.md` body containing
  `<!-- include: ... -->` markers to RemoteTrigger. Always render via
  `scripts/render-routine.sh` first; the deployed blob is the rendered
  output. Refuse to deploy any file whose render fails.
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
- Deployed routines FATAL with `403 "not enabled for this session"`
  on every GitHub call — the claude.ai account's GitHub connection is
  stale (e.g. after an account/org rename). The USER must re-run
  `/web-setup` on claude.ai; no prompt or env change helps. Deploying
  is still safe (the body update is Anthropic-side), but smoke runs
  will fail until the connection is re-bound.
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
