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

### Staggered deploy after multi-routine merges

When a single PR rewrites multiple routine prompts (e.g. PR #20),
do NOT deploy all updates in one `RemoteTrigger update` burst.
Stage by blast radius and watch each stage for 48 hours:

1. **Stage 1 (Day 0)** — read-mostly routines (Inspector, Sentinel,
   The Observer). Watch 48h.
2. **Stage 2 (Day 2)** — label-only / config-only mutations
   (Apothecary, Quartermaster, Daily Polish). Watch 48h.
3. **Stage 3 (Day 4)** — high-mutation routines (Archivist,
   Conductor, Custodian, The Solver). Watch 48h.

If a stage produces unexpected PRs/issues/merges, halt subsequent
stages, set `ROUTINE_PAUSED=true` on the misbehaving routine via
the claude.ai web UI, and fix forward.

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
5. **Paused flag.** Every routine checks `${ROUTINE_PAUSED}` at the
   top of its main task. If set (any non-empty value), emit a
   single Slack message `🛑 <Routine> paused via env` and exit.
   This is the kill switch for a misbehaving routine — setting the
   env var on the claude.ai web UI takes effect on the next cron
   tick without a redeploy.
6. **Body redaction before any commit/issue/PR composition.** Every
   string fetched from outside the routine (file bodies, PR titles,
   issue bodies, alert names, commit messages) and destined for
   GitHub or Slack MUST pass through the redaction regex set
   before being written. Canonical regex set:

   ```text
   s|/Users/[^/]+/|/Users/<redacted>/|g
   s|\$\{GIT_HOME[A-Z_]*\}|<path>|g
   s|GH_PAT_[A-Z]+|<secret>|g
   s|sk-ant-[A-Za-z0-9_-]+|<key>|g
   s|gh[ps]_[A-Za-z0-9]+|<key>|g
   s|\b\d{12}\b|<aws-account>|g
   ```

   Skip-list when scanning source files: `*.local.md`, `.envrc`,
   `.envrc.local`, `CLAUDE.local.md`. A redacted match in a
   Provenance "Why" line MUST describe the rule that fired, not
   quote the offending string.
7. **Slack output sanitization.** Slack's `<!channel>`, `<!here>`,
   `<@USERID>`, `<#CHANNEL>`, `<URL|text>` tokens can be smuggled
   through PR titles, issue bodies, alert names. Every Slack-emit
   path MUST escape `<` → `‹` and `>` → `›` in any field derived
   from repo content:

   ```bash
   safe() { jq -Rr 'gsub("<"; "‹") | gsub(">"; "›")'; }
   echo "${untrusted_title}" | safe
   ```

8. **State gist convention.** Each routine that holds cross-run
   memory uses one private GitHub Gist named `<routine>-state`
   (e.g. `archivist-state`). Schema:

   ```json
   {
     "schema_version": 2,
     "prompt_sha256": "abc123…",
     "run_log": [
       {"ts":"2026-05-25T14:00:00Z","repo":"JacobPEvans/nix-darwin",
        "action":"pr_opened","resource_id":"https://github.com/...","reason":""}
     ],
     "closed_pairs": {"JacobPEvans/foo": ["bar.yml"]},
     "cooldowns": {"JacobPEvans/foo": "2026-06-01T00:00:00Z"}
   }
   ```

   Retention is per-field, not blanket: `run_log` trimmed to 90
   days (archive overflow to sibling gist `<routine>-state-archive`),
   `closed_pairs` and `apothecary-codeql-ignore` retained
   **indefinitely** (rejection memory must outlive trim windows),
   cooldowns trim once expired. Hard cap 1 MB per gist. Never
   write secrets, raw alert payloads, full PR diffs, or repo file
   contents to a state gist — `run_log.reason` is bounded to 200
   chars after redaction (rule 6).

9. **Per-repo PR budget.** PR-emitting routines (Inspector,
   Quartermaster, Archivist Task 1) consult a shared
   gist `routine-pr-budget` before opening a PR. Schema:

   ```json
   {
     "2026-05-25": {"JacobPEvans/nix-darwin": 1,
                    "JacobPEvans/ai-workflows": 2}
   }
   ```

   Soft cap: **2 PRs per repo per UTC day across all routines**
   (Conductor merges don't count). Read the day's counter, skip
   the repo if at cap, otherwise increment and proceed.
   Concurrency posture is best-effort, not exactly-once — cron
   stagger keeps near-misses rare. If the gist is missing,
   corrupted, or returns non-JSON: fail open (proceed with the
   routine's own per-run cap) AND emit a Slack warning.

10. **Prompt fingerprint logging.** Each run appends one
    `prompt_sha256` entry to the state gist (overwrites the
    previous entry — only the most-recent fingerprint is needed).
    Sentinel cross-checks this against `sha256` of the prompt file
    at HEAD of `main` in `JacobPEvans/claude-code-routines`; a
    mismatch indicates the cloud deployment is stale or has been
    mutated out-of-band.

## Attribution conventions

Every PR or issue created by a cloud routine MUST be self-identifying.
Three layers: title suffix → label → body Provenance block. The user
can't tell which routine made a PR if any of these are missing.

These rules apply to all PR-creating routines (Daily Polish, Sentinel,
Inspector, Quartermaster, Archivist, Apothecary, The Solver) and all
issue-creating routines (Custodian's repo-audit, Archivist's
private-docs issue, Sentinel's secret alerts if filed).

### Title

```text
<conventional-prefix>(<scope>): <description> [routine:<basename>]
```

`<basename>` matches the routine file basename (`daily-polish`,
`issue-solver`, etc.). Title must NOT contain emoji
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

Examples: `docs/daily-polish/int_homelab-2026-05-23`. Avoid
collisions across runs by always including the date in the branch
name.

### Review-ready, not draft (with one exception)

`gh pr create` calls do NOT pass `--draft`. PRs open review-ready so
the `ai-workflows` review workflows (`claude-review`,
`final-pr-review`, `ai-merge-gate`) pick them up immediately.
Routines never auto-merge; merges go through the normal review flow
or `The Conductor`'s strict bot-author allowlist (which routine bots
are NOT a member of).

**Exception** — PRs that modify `.github/workflows/*.yml` MUST pass
`--draft`. Inspector's `no-scripts` rule (extracts inline workflow
logic into `scripts/`) does this. Draft forces explicit human
ready-flip before any auto-review fires; broken YAML never lands.

## Out of scope for this repo

- Cron, MCP connectors, environment variables, run history — managed in
  the web UI at `claude.ai/code/routines`.
- Per-run secrets — stored in the cloud environment (`env_*`).
