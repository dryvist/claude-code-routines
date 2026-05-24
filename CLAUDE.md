# Claude Code Routines — Operator Guide

This repo is the source of truth for twelve cloud routines hosted on
Anthropic's Claude Code platform. Files in `routines/*.prompt.md` are the
versioned prompts; the cloud manages execution.

## Routine inventory

`trigger_id`s are pinned in each file's YAML frontmatter — never change
them. A new value means a new cloud routine, not an update.

| Routine | File basename | Cron (UTC) |
| --- | --- | --- |
| Issue Solver | `issue-solver` | `0 0,12 * * *` |
| Daily Polish | `daily-polish` | `0 4 * * *` |
| The Sentinel | `sentinel` | `33 5 * * *` |
| The Inspector | `inspector` | `0 6 * * *` |
| The Custodian | `custodian` | `0 7 * * *` |
| The Quartermaster | `quartermaster` | `0 8 * * *` |
| The Archivist | `archivist` | `0 9 * * *` |
| Morning Briefing | `morning-briefing` | `0 10 * * *` |
| The Conductor | `conductor` | `15 11,17 * * *` |
| The Apothecary | `apothecary` | `0 13 * * *` |
| The Distributor | `distributor` | `0 14 * * *` |
| Weekly Scorecard | `weekly-scorecard` | `0 10 * * 1` |

Files live under `routines/<basename>.prompt.md`.

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

## Attribution conventions

Every PR or issue created by a cloud routine MUST be self-identifying.
Three layers: title suffix → label → body Provenance block. The user
can't tell which routine made a PR if any of these are missing.

These rules apply to all PR-creating routines (Daily Polish, Sentinel,
Inspector, Quartermaster, Archivist, Apothecary, Distributor,
Issue Solver) and all issue-creating routines (Custodian's repo-audit,
Archivist's private-docs issue, Sentinel's secret alerts if filed).

### Title

```text
<conventional-prefix>(<scope>): <description> [routine:<basename>]
```

`<basename>` matches the routine file basename (`daily-polish`,
`distributor`, `issue-solver`, etc.). Title must NOT contain emoji
(soul rule: no emoji in commit messages, PR titles, PR descriptions,
or release notes). Conventional-commit prefix is preserved so
release-please continues to parse it.

For issues (no conventional prefix needed):

```text
[routine:<basename>] <description>
```

### Body — Provenance block at the bottom

Every PR body and every issue body ends with this block:

```markdown
---

## Provenance

- **Generated by:** [<Routine Name>](<prompt file URL>) -
  cloud routine, <cron description>
- **Triggered:** <what fired this run (cron + task selection if any)>
- **Why this PR/issue:** <one-line rationale tying the selection
  algorithm to this specific output>
- **State:** [<gist name>](<gist URL>)
- **Label:** `cloud-routine`
```

The block is appended; the rest of the body remains whatever the
routine already writes. No emoji in the body either.

### Label

Apply the `cloud-routine` label after creating the PR or issue:

```bash
gh pr edit "$PR_NUMBER" --repo "$OWNER/$REPO" --add-label cloud-routine
gh issue edit "$ISSUE_NUMBER" --repo "$OWNER/$REPO" --add-label cloud-routine
```

The label is defined in `JacobPEvans/.github/.github/labels.yml` and
propagated to every public repo by the `label-sync.yml` workflow —
routines do NOT need to `gh label create` per repo. If a label-add
call fails because the target repo is private and outside the sync
list, log a warning in Slack but proceed.

### Branch naming

Per-run, dated, namespaced:

```text
<type>/<routine-basename>/<slug>-<YYYY-MM-DD>
```

Examples: `chore/distributor/add-gh-aw-pin-refresh-2026-05-23`,
`docs/daily-polish/int_homelab-2026-05-23`. Avoid collisions across
runs by always including the date in the branch name.

### Review-ready, not draft

`gh pr create` calls do NOT pass `--draft`. PRs open review-ready so
the `ai-workflows` review workflows (`claude-review`,
`final-pr-review`, `ai-merge-gate`) pick them up immediately.
Routines never auto-merge; merges go through the normal review flow
or `The Conductor`'s strict bot-author allowlist (which routine bots
are NOT a member of).

## Out of scope for this repo

- Cron, MCP connectors, environment variables, run history — managed in
  the web UI at `claude.ai/code/routines`.
- Per-run secrets — stored in the cloud environment (`env_*`).
