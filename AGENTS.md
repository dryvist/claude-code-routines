# Claude Code Routines — Operator Guide

This repo is the source of truth for five cloud routines hosted on
Anthropic's Claude Code platform. Files in `routines/*.prompt.md` are the
versioned prompts; the cloud manages execution.

## Routine inventory

`trigger_id`s are pinned in each file's YAML frontmatter — never change
them. A new value means a new cloud routine, not an update.

| Routine | File basename | Cron (UTC) |
| --- | --- | --- |
| Daily Polish | `daily-polish` | `0 4 * * *` |
| The Sentinel | `sentinel` | `33 5 * * *` |
| The Custodian | `custodian` | `0 7 * * *` |
| Docs Sync | `docs-sync` | `13 8 * * *` |
| The Observer | `observer` | `0 10 * * *` |

Files live under `routines/<basename>.prompt.md`.

`The Solver` (file basename `issue-solver`, cron `0 0,12 * * *`) runs as
a GitHub Actions workflow (`.github/workflows/issue-solver.yml`), not as
a cloud routine — no `trigger_id` in its frontmatter. It's listed here
for completeness but is not deployed via the cloud-routine path.

## Retired routines

### Weekly Scorecard (retired 2026-05-30)

- **trigger_id:** `trig_01TGiH3VuW5Xp7Ej9wSQFvpq`
- **Replacement:** Merged into The Observer (Monday code path).
- **State migration:** On The Observer's first run, the legacy
  `weekly-scorecard-state` gist is read, scorecard data copied into the
  new `observer-state` gist's `scorecard_history` field, then the legacy
  gist deleted.

### The Distributor (retired 2026-05-30)

- **trigger_id:** `trig_01HoVTrJjo41JFEyzmY1tU5b`
- **Replacement:** `dryvist` org-level Required Workflows (configured
  manually via org settings). Per-tier opt-out moves from
  `skip-distributor-<tier>` topics to explicit repo-list exclusion in
  the org Required Workflow selector.
- **Migration runbook:** see
  [`docs/DISTRIBUTOR_RETIREMENT.md`](docs/DISTRIBUTOR_RETIREMENT.md).
- **Scope note:** `JacobPEvans-personal/*` repos lose tier-workflow
  coverage. Required Workflows only apply to org-owned repos. Migrate
  to dryvist or accept drift.

## Deploying a prompt change

The cloud routine has its own copy of each prompt. Editing a `.prompt.md`
file does **not** change cloud behaviour on its own — the change must be
pushed to the Anthropic Routines API.

### Active path: Claude in an interactive session

The Anthropic Routines API does not currently accept the OAuth tokens
that claude.ai issues for this account — `RemoteTrigger` calls from
`anthropics/claude-code-action@v1` return
`Unable to resolve organization UUID`. The GHA workflow at
`.github/workflows/deploy-routines.yml` is therefore disabled (see its
header for full diagnosis). While the token issue is upstream-blocked,
cloud routines are kept in sync by Claude itself during editing
sessions:

1. Edit a `routines/*.prompt.md` file as usual.
2. A repo-level hook in `.claude/settings.json` reminds Claude to
   invoke the project skill at
   [`.claude/skills/deploy-routine-changes/SKILL.md`](.claude/skills/deploy-routine-changes/SKILL.md).
3. The skill walks Claude through `RemoteTrigger get` / `update` /
   `create` calls (the interactive harness has working auth) and,
   for new routines, opens a small follow-up PR to back-commit the
   issued `trigger_id`.

The skill is the single source of truth for the procedure. Don't
duplicate it here.

### Re-enabling the GHA workflow

When the OAuth token starts carrying the org UUID (Anthropic-side
fix), restore the `on:` block in
`.github/workflows/deploy-routines.yml` and remove the DEPRECATED
banner from `.github/workflows/prompts/deploy-routines.prompt.md`.
Update this section to point at the workflow as the primary path
again.

### Fallback: `/schedule update` from the CLI

If Claude's RemoteTrigger access ever stops working too, the
last-resort path is the `/schedule update` CLI flow:

```text
> /schedule list      # confirm trigger_id
> /schedule update    # pick the routine, paste the new prompt
```

Do **not** paste into the web UI — the whole point of versioning
these files is keeping cloud and repo in lockstep.

## Hard rules for routine prompts

These rules apply to every routine that mutates GitHub state. Bake them
into the prompt body, not into developer memory — the cloud sandbox
cannot read this file at run-time. Operator setup lives in
[`docs/CLOUD_ROUTINES_AUTH.md`](docs/CLOUD_ROUTINES_AUTH.md);
canonical signing architecture lives in your team's signing rule doc
(if you don't have one, the operator runbook above describes the full
identity/auth/signing model in one place).

1. **All commits via GitHub Contents API.** Auth is the long-lived PAT
   in `GH_TOKEN`; identity comes from `GIT_COMMITTER_NAME` /
   `GIT_COMMITTER_EMAIL` env vars passed as a nested `committer` object
   in the PUT body. `gh api -f key.subkey=val` flattens the dot —
   build the payload with `jq` and pipe it via `--input -`. GitHub
   web-flow signs the commit; `author.login` surfaces as the bot
   identity configured in `GIT_COMMITTER_NAME`. `git commit` is
   forbidden (unsigned).
2. **No local branches.** Use `gh api repos/.../git/refs` for branch
   creation, not `git checkout -b … && git push`.
3. **`Write` / `Edit` are permitted** for local scratch (e.g. building
   file content before base64-encoding into a Contents API PUT). The
   `git commit` / `git push` prohibition is enforced by prompt rules,
   not `allowed_tools` (Bash subcommands aren't filterable).
4. **No fictional env vars.** The cloud sandbox does not inject a
   session-ID variable. References like
   `${CLAUDE_CODE_REMOTE_SESSION_ID}` render literally. If you need a
   session link, there isn't one.

## Out of scope for this repo

- Cron, MCP connectors, environment variables, run history — managed in
  the web UI at `claude.ai/code/routines`.
- Per-run secrets — stored in the cloud environment (`env_*`).
