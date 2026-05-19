# Claude Code Routines — Operator Guide

This repo is the source of truth for six cloud routines hosted on
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
| Issue Solver | `issue-solver` | `0 0,12 * * *` |
| Morning Briefing | `morning-briefing` | `0 10 * * *` |
| Weekly Scorecard | `weekly-scorecard` | `0 10 * * 1` |

Files live under `routines/<basename>.prompt.md`.

## Deploying a prompt change

The cloud routine has its own copy of each prompt. Editing a `.prompt.md`
file does **not** change cloud behaviour on its own — the change must be
pushed to the Anthropic Routines API.

### Canonical: GitHub Action (manual or daily schedule)

`.github/workflows/deploy-routines.yml` runs `anthropics/claude-code-action@v1`
on two triggers: `workflow_dispatch` (manual) and a daily cron at 06:00 UTC
(self-healing safety net). The action's instructions live in
`.github/workflows/prompts/deploy-routines.prompt.md` — keeping the deploy
prompt out of the YAML so it's diff-friendly and easy to edit.

Auth is `CLAUDE_CODE_OAUTH_TOKEN` (sync'd from your secret store of
choice into the workflow's `secrets.*`). The action gives Claude
the built-in `RemoteTrigger` tool, which talks to Anthropic's
internal Routines API. The deploy prompt does a `get` before each `update`
and skips files already in sync — so the daily run is near-zero-cost when
nothing has changed.

After merging a prompt change to `main`, trigger an immediate deploy with:

```bash
gh workflow run deploy-routines.yml --ref main
```

### Manual fallback: `/schedule update` from the CLI

In any Claude Code session:

```text
> /schedule list      # confirm trigger_id
> /schedule update    # pick the routine, paste the new prompt
```

Use this only when CI is unavailable. Do **not** paste into the web UI —
the whole point of versioning these files is keeping cloud and repo in
lockstep.

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
