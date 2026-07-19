---
name: Deploy routine changes
description: >-
  Use whenever the pinned `vendor/ai-llm-prompts` routine catalog or
  local `routines/registry.yaml` deployment metadata changes. The GHA deploy
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

- The pinned `vendor/ai-llm-prompts` commit changed and its automation
  catalog contains a routine prompt or fragment change.
- Local deployment metadata in `routines/registry.yaml` changed.
- The user merged either change and you are picking up afterward.
- Drift is suspected even without a recent edit.

## Step 1 — Identify routines to sync

The Git submodule is the immutable prompt source. If its gitlink changed,
inspect the old-to-new catalog diff for `automation/routine-*.md`.
A fragment change affects every prompt containing that fragment marker.
If the affected set cannot be proven narrowly, sync all cloud routines
listed in `routines/registry.yaml`; the drift check prevents unnecessary
updates. The GHA-managed `issue-solver` is never a cloud deploy target.

If only `routines/registry.yaml` changed, select the entries whose
deployment metadata changed. If nothing changed and no drift is suspected,
stop here.

## Step 2 — Per routine: read metadata, then render

`routines/registry.yaml` owns `name`, `trigger_id`, `cron`,
`allowed_tools`, MCP connections, and `autofix`. The catalog owns only
the model-directed body and its reusable fragments.

Render the selected routine by basename:

```bash
scripts/render-routine.sh <basename> > /tmp/<basename>.rendered.md
```

The renderer strips catalog OKF registry entry and expands every flattened
`routine-fragment-<name>.md` marker. Its output is the complete prompt
BODY sent to RemoteTrigger. If rendering fails, report
`FAIL <basename> (render error)` and do not deploy it.

Also read the pinned cloud environment and default model:

```bash
ENVIRONMENT_ID=$(
  grep -m1 '^ENVIRONMENT_ID=' routines/_common/deploy.config |
    cut -d= -f2 | tr -d '\r'
)
MODEL=$(
  grep -m1 '^CLAUDE_SONNET_MODEL_ID=' routines/_common/deploy.config |
    cut -d= -f2 | tr -d '\r'
)
```

Every create/update uses the registry entry plus `$ENVIRONMENT_ID`.
A registry `model` overrides `$MODEL`; absent `autofix` means
`false`.

## Step 3 — Decide what to do per registry entry

| `trigger_id` | `cron` | Action |
| --- | --- | --- |
| absent | absent | SKIP — GHA-managed (`issue-solver`) |
| absent | present | CREATE — follow Step 4 |
| present | (any) | UPDATE-IF-DRIFTED — follow Step 5 |

## Step 4 — Create a new cloud routine

The Routines API requires `job_config.ccr.environment_id` and a few
other top-level fields that are easy to drop. The reliable path:
**fetch the canonical shape from an existing routine first, then
substitute only the per-routine fields.**

1. Pick any sibling registry entry with a `trigger_id` (e.g.
   `docs-polish`). Call:

   ```text
   RemoteTrigger action=get trigger_id=<sibling-trigger-id>
   ```

2. From the response, build the create body by **deep-copying the
   entire `job_config` and every top-level field**, then substituting
   only:

   - top-level `name` ← new file's registry entry `name`
   - top-level `cron_expression` ← new file's registry entry `cron`
     (note the rename: API field is `cron_expression`, registry entry
     field is `cron`)
   - `job_config.ccr.session_context.allowed_tools` ← registry entry
     `allowed_tools`
   - `job_config.ccr.session_context.model` ← registry entry `model`
     if present, else `$MODEL` from `routines/_common/deploy.config`
   - `job_config.ccr.session_context.autofix_on_pr_create` ←
     registry entry `autofix` (absent → `false`)
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
   registry entry immediately after the `name:` line. Don't reorder
   anything else.

6. Commit and push the trigger_id back-commit via the normal
   local git flow (worktree → branch → commit → push →
   `gh pr create`). Keep the diff to the one registry entry line — a
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
   RENDERED BODY, `$ENVIRONMENT_ID`, and the registry entry `autofix`
   from Step 2. Normalize both `autofix_on_pr_create` and registry entry
   `autofix` to `false` when absent or `null` before comparing — older
   routines may lack the field and the API may omit falsey values.

3. **In sync only if ALL THREE match**: CLOUD_BODY == RENDERED BODY,
   `environment_id` == `$ENVIRONMENT_ID`, and `autofix_on_pr_create`
   == registry entry `autofix`. If so, report `SKIP <basename> (in sync)`
   and move on. (Body-only checks let an out-of-band env or autofix
   drift slip through — that is exactly the bug this guards against.)

4. If any differ: show the operator the body diff (write CLOUD_BODY
   and RENDERED BODY to temp files, `diff -u`) and note any env /
   autofix change. Then build the update body by deep-copying the get
   response and substituting only:

   - `job_config.ccr.events[0].data.message.content` ← RENDERED BODY
   - `job_config.ccr.session_context.allowed_tools` ← registry entry
     `allowed_tools`
   - `job_config.ccr.session_context.model` ← registry entry `model`
     if present, else `$MODEL` from `routines/_common/deploy.config`
   - `job_config.ccr.session_context.autofix_on_pr_create` ←
     registry entry `autofix` (absent → `false`)
   - `job_config.ccr.environment_id` ← `$ENVIRONMENT_ID`
   - top-level `cron_expression` ← registry entry `cron`

   If the registry entry `name` differs from the trigger's top-level
   `name` (a rename), also substitute:

   - top-level `name` ← registry entry `name`

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
   == registry entry `autofix`. If any check fails, surface it in the
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

- **Never** send a raw catalog prompt containing unresolved include markers
  to RemoteTrigger. Always render via
  `scripts/render-routine.sh` first; the deployed blob is the rendered
  output. Refuse to deploy any file whose render fails.
- **Never** call `gh workflow run deploy-routines.yml`. The workflow
  is disabled; running it produces no-op success and confuses the
  signal.
- **Never** modify the `issue-solver` registry entry and expect this
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
