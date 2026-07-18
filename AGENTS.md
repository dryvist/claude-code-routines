# Claude Code Routines — Operator Guide

This repo owns deployment metadata and consumers for cloud routines hosted on
Anthropic's Claude Code platform. Prompt bodies are pinned from
`dryvist/ai-llm-prompts` through `vendor/ai-llm-prompts`; the cloud manages
execution.

## Routine inventory

The registry (routine names, files, crons, purposes) lives in the
[README `Routines` table](README.md#routines) — single canonical home,
do not duplicate it here. Every live cloud trigger MUST map to one entry in
`routines/registry.yaml`, matched by its pinned `trigger_id`, and one central
catalog prompt — or be disabled. `trigger_id`s are pinned; never change them.
A new value means a new cloud routine, not an update.

`issue-solver` (cron `0 0,12 * * *`) runs as a GitHub Actions workflow
(`.github/workflows/issue-solver.yml`), not as a cloud routine — no
`trigger_id` in its registry entry. It's listed in the registry for completeness
but is not deployed via the cloud-routine path.

## Naming convention (2026-07 consolidation)

One functional kebab-case token per routine, used identically everywhere:
registry `name`, prompt basename, attribution tag `[routine:<name>]`,
state file `state/<name>.json`, Slack header, and branch prefix. No
display names, no personas — the old "The Observer"-style names created
three-token drift (display vs basename vs tag). Rename ledger (trigger_ids
stay pinned across renames):

- `estate-briefing` ← The Observer
  (`trig_01TUW8LMXob53okTF8juhkA8`)
- `repo-audit` ← The Inspector
  (`trig_01Kaa2rWoVFS4HN4LRR5UMWX`)
- `estate-janitor` ← The Custodian
  (`trig_01PQsM64nMfQRYptyihRr3Er`)
- `precommit-bump` ← The Quartermaster
  (`trig_017wzm9n7a8v2yh3tfAsnmg8`)
- `bot-pr-merge` ← The Conductor, absorbing The Apothecary
  (`trig_01N7W9LBApg9veyo2NgdprNV`)
- `docs-polish` ← Daily Polish, absorbing the Archivist readme task
  (`trig_01V6C6j9FHn21pk11YfrjURH`)
- `docs-sync` ← Docs Sync, name normalized
  (`trig_01J9F82aQp1NX5W8PcvSXyh6`)
- `issue-solver` ← The Solver, name normalized (GHA — no trigger)
- The Apothecary's own trigger `trig_015zNd6NJRJZCd784qX5FEgm` and the
  Archivist's `trig_01U6EPmvAdUDy2k7LfYWkqts`: DISABLED, never reuse.

## Retired routines

### The Apothecary (merged 2026-07-02)

- **trigger_id:** `trig_015zNd6NJRJZCd784qX5FEgm` — disabled, never reuse.
- **Replacement:** Phase A of `bot-pr-merge` (security triage runs
  immediately before the merge pass, twice daily). Rationale: Apothecary's
  `auto-merge-deps` labels were inert until Conductor ran; one routine
  removes the coupling.

### The Archivist (merged 2026-07-02)

- **trigger_id:** `trig_01U6EPmvAdUDy2k7LfYWkqts` — disabled, never reuse.
- **Replacement:** the `readme-quality` task merged into `docs-polish`
  (estate-wide 8-check scoring); the `mintlify-coverage` task demoted to a
  read-only Monday scorecard line in `estate-briefing` (closes the issue
  #24 evaluation — the issue-filing path never proved its hit rate).

### Legacy Issue Solver cloud trigger (disabled 2026-07-02)

- **trigger_id:** `trig_01W4LiFv6S6uAf53UoBKrhsX` — disabled, never reuse.
- The Solver moved to GitHub Actions (`issue-solver.yml`) long before, but
  the old cloud trigger was still enabled and shadowing the GHA run.

### Weekly Scorecard (retired 2026-05-30, reused 2026-06-09, fully retired 2026-07-01)

- **trigger_id:** `trig_01TGiH3VuW5Xp7Ej9wSQFvpq`
- **2026-05-30:** GitHub repo-health scoring merged into The Observer
  (Monday code path). Repo-health scoring stays in The Observer.
- **2026-06-09:** The dormant trigger was reused for a disjoint scope —
  Estate Consolidation 2026-06 Linear project reporting.
- **2026-07-01:** Fully retired. The Estate Consolidation project was
  time-boxed (completion target 2026-07-12); the routine was Linear-only,
  read-only, held no GitHub state, and was never affected by the gist
  outage. Source file `routines/weekly-scorecard.prompt.md` removed;
  **disable this trigger in the cloud** as part of the repo-file-state
  deploy. Do not reuse the trigger again without a fresh decision.

### The Sentinel (retired 2026-07-01)

- **trigger_id:** `trig_012Qm47ALSKohLHapA1pD9t1`
- **Replacement:** none. Retired as low-value: it opened one PR/day of
  hardcoded-literal parameterization nits, and its *documented* role as
  the `prompt_sha256` cross-check monitor (former hard rule 10) was never
  actually implemented in the prompt. Source file
  `routines/sentinel.prompt.md` removed; trigger disabled in the cloud
  2026-07-02 (it had kept firing after retirement — the gap that
  motivated the monitor). The real out-of-band liveness/drift monitor
  now exists: `.github/workflows/routine-monitor.yml` (hard rule 11).

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

## DRY partials and deploy-time assembly

The pinned catalog under `vendor/ai-llm-prompts/automation/` owns routine
prompt bodies and flattened `routine-fragment-*.md` partials. Local
`routines/registry.yaml` owns trigger IDs, cron schedules, allowed tools,
MCP connections, and autofix settings; `routines/_common/deploy.config`
retains the cloud environment and default model pins.

A central routine includes a fragment with exactly:

```text
<!-- include: routine-fragment-<name>.md -->
```

`scripts/render-routine.sh <basename>` strips OKF frontmatter and expands
those markers. It exits nonzero on missing or nested fragments. The deployed
blob is always this rendered body. CI renders all eight prompts, and
`issue-solver.yml` reads a rendered workspace file.

The operator-facing hard rules below remain descriptive. Model-directed rule
text belongs in the central prompt catalog.

## Deploying a prompt change

The cloud routine has its own deployed copy of each prompt. Advancing the
catalog gitlink does **not** change cloud behaviour on its own — the selected
central prompt must be rendered and pushed to the Anthropic Routines API.

### Active path: Claude in an interactive session

The Anthropic Routines API does not currently accept the OAuth tokens
that claude.ai issues for this account — `RemoteTrigger` calls from
`anthropics/claude-code-action@v1` return
`Unable to resolve organization UUID`. The GHA workflow at
`.github/workflows/deploy-routines.yml` is therefore disabled (see its
header for full diagnosis). While the token issue is upstream-blocked,
cloud routines are kept in sync by Claude itself during editing
sessions:

1. Release the central prompt change and advance the pinned catalog gitlink.
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
`.github/workflows/deploy-routines.yml` and update the central
`routine-deploy-reference.md` status.
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

When a single PR rewrites multiple routine prompts, do NOT deploy all
updates in one blind `RemoteTrigger update` burst. Order by blast
radius, smoke-test each deploy, and pair merge-away disables with their
absorbing routine's update:

1. **Read-mostly first** — `estate-briefing` (the canonical smoke test
   for the state-file + preflight + token stack), then `repo-audit`.
   `RemoteTrigger action=run` once and confirm a sane Slack message and
   a state-file write before proceeding.
2. **Config/docs mutations** — `precommit-bump`, `docs-sync`,
   `docs-polish`.
3. **High-mutation last** — `estate-janitor`, then `bot-pr-merge`
   (it merges PRs — watch its first run live: labels ≤5, merges gated).

Rules that always apply:

- **Save a rollback body.** Before every `update`, save the full
  `RemoteTrigger get` response; any stage can then be reverted verbatim.
- **Pause lever is per-trigger `enabled: false`** —
  `RemoteTrigger action=update trigger_id=<id> body={"enabled": false}`,
  verify with `get`. `ROUTINE_PAUSED` is an env var on the SINGLE shared
  cloud environment: setting it pauses EVERY routine, not one. Use it
  only as the estate-wide kill switch.
- **Merges pair disable-then-update.** When routine B absorbed routine
  A, disable A's trigger and update B's in the same sitting — the
  coverage gap is minutes, dual-coverage never happens.
- If a deploy misbehaves: `enabled: false` that trigger, restore the
  saved body, fix forward.

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
   single Slack message `🛑 <routine> paused via env` and exit.
   NOTE: the env var lives on the single shared cloud environment, so
   setting it pauses EVERY routine — it is the estate-wide kill
   switch. The per-routine pause lever is the trigger's top-level
   `enabled: false` (see the deploy runbook). Both take effect on the
   next cron tick without a redeploy.
6. **Connectivity preflight (fail loud).** Immediately after the
   paused check and before any GitHub enumeration or state I/O, every
   routine runs the `preflight.md` canaries (auth + REST egress). On
   failure it emits a distinct `🔴 <routine> FATAL: <cause>` Slack
   message and exits — it MUST NOT fall through to a "no findings ✓"
   success. This exists because an invalid token or a blocked/`502`
   egress otherwise yields empty enumeration that reads as a healthy
   quiet estate. `🔴` = infra-fatal; `🛑` = paused. Empty results are
   only ever reported after the preflight passes.
7. **Body redaction before any commit/issue/PR composition.** Every
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
8. **Slack output sanitization.** Slack's `<!channel>`, `<!here>`,
   `<@USERID>`, `<#CHANNEL>`, `<URL|text>` tokens can be smuggled
   through PR titles, issue bodies, alert names. Every Slack-emit
   path MUST escape `<` → `‹` and `>` → `›` in any field derived
   from repo content:

   ```bash
   safe() { jq -Rr 'gsub("<"; "‹") | gsub(">"; "›")'; }
   echo "${untrusted_title}" | safe
   ```

9. **State file convention.** Cloud routines cannot write gists (the
   egress proxy blocks gist writes, HTTP 403). Each routine that holds
   cross-run memory uses one private JSON file `state/<routine>.json`
   on the **`data` branch** of `$STATE_REPO` (a `$GH_OWNER` repo; state
   uses `data` because the org ruleset makes `main` PR-only), read/written
   through the Contents API with SHA optimistic locking (see
   the central `routine-fragment-state-file.md`). This includes the GHA-managed
   `issue-solver` (its 2026-07 migration retired the last gist). Schema:

   ```json
   {
     "schema_version": 2,
     "prompt_sha256": "abc123…",
     "run_log": [
       {"ts":"2026-05-25T14:00:00Z","repo":"dryvist/nix-darwin",
        "action":"pr_opened","resource_id":"https://github.com/...","reason":""}
     ],
     "closed_pairs": {"dryvist/foo": ["bar.yml"]},
     "cooldowns": {"dryvist/foo": "2026-06-01T00:00:00Z"}
   }
   ```

   Retention is per-field, not blanket: `run_log` trimmed to 90
   days (archive overflow to sibling file `state/<routine>-archive.json`),
   `closed_pairs` and `codeql_ignore` retained
   **indefinitely** (rejection memory must outlive trim windows),
   cooldowns trim once expired. Hard cap ~1 MB per file. Never
   write secrets, raw alert payloads, full PR diffs, or repo file
   contents to a state file — `run_log.reason` is bounded to 200
   chars after redaction (rule 7).

10. **Per-repo PR budget.** PR-emitting routines (repo-audit,
    precommit-bump, docs-polish) consult the shared file
    `pr-budget.json` at the `$STATE_REPO` root before opening a PR.
    Schema:

    ```json
    {
      "2026-05-25": {"dryvist/nix-darwin": 1,
                     "dryvist/ai-workflows": 2}
    }
    ```

    Soft cap: **2 PRs per repo per UTC day across all routines**
    (bot-pr-merge merges don't count). Read the day's counter, skip
    the repo if at cap, otherwise increment and proceed (Contents API
    SHA lock; retry once on 409). Concurrency posture is best-effort,
    not exactly-once — cron stagger keeps near-misses rare. If the file
    is missing, corrupted, or returns non-JSON: fail open (proceed with
    the routine's own per-run cap) AND emit a Slack warning.

11. **Prompt fingerprint (written AND consumed).** Each run overwrites
    the state file's `prompt_sha256` with the SHA-256 of the prompt
    body it received (exact recipe in the central
    `routine-fragment-state-file.md`). The consumer is
    `.github/workflows/routine-monitor.yml` — a daily
    GHA-scheduled checker (App token, independent of `GH_TOKEN`) that
    compares each state file's fingerprint against the rendered repo
    prompt (drift) and checks the state file's last-write age
    (liveness), maintaining a single tracking issue in this repo.
    A DRIFT finding right after a routine PR merges is the designed
    "you forgot to deploy" signal.

12. **Single-owner scope.** Every routine operates on exactly one
    configured owner (`$GH_OWNER`, default `dryvist`). No routine
    enumerates a multi-owner list — do not reintroduce a `$GH_OWNERS`
    variable or a comma-split owner loop. The runtime `GH_TOKEN` (a
    fine-grained PAT, resource owner `$GH_OWNER`) MUST be scoped to the
    `$GH_OWNER` operational repos **plus `$STATE_REPO`** (the cross-run
    state store, also under `$GH_OWNER`) — and nothing else. That token
    scope is the authoritative backstop: a prompt slip or misconfigured
    env var can never mutate a repo outside `$GH_OWNER`.

## Attribution conventions

Every PR or issue created by a cloud routine MUST be self-identifying.
Three layers: title suffix → label → body Provenance block. The user
can't tell which routine made a PR if any of these are missing.

These rules apply to all PR-creating routines (docs-polish, repo-audit,
precommit-bump, docs-sync, issue-solver) and all issue-creating
routines (estate-janitor's repo-health audit, repo-audit's
secrets-policy issue).

### Title

```text
<conventional-prefix>(<scope>): <description> [routine:<basename>]
```

`<basename>` matches the routine file basename (`docs-polish`,
`issue-solver`, etc. — identical to the routine's `name` under the
naming convention above). Title must NOT contain emoji
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
- **State:** `state/<basename>.json` in `$STATE_REPO`
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

The label is defined in `dryvist/.github/.github/labels.yml` and
propagated to every public repo by the `label-sync.yml` workflow —
routines do NOT need to `gh label create` per repo. If a label-add
call fails because the target repo is private and outside the sync
list, log a warning in Slack but proceed.

### Branch naming

Per-run, dated, namespaced:

```text
<type>/<routine-basename>/<slug>-<YYYY-MM-DD>
```

Examples: `docs/docs-polish/int_homelab-2026-07-02`. Avoid
collisions across runs by always including the date in the branch
name.

### Review-ready, not draft (with one exception)

`gh pr create` calls do NOT pass `--draft`. PRs open review-ready so
the `ai-workflows` review workflows (`claude-review`,
`final-pr-review`, `ai-merge-gate`) pick them up immediately.
Routines never auto-merge; merges go through the normal review flow
or `bot-pr-merge`'s strict bot-author allowlist (which routine bots
are NOT a member of).

**Exceptions** — PRs that modify `.github/workflows/*.yml` MUST pass
`--draft`. repo-audit's `no-scripts` rule (extracts inline workflow
logic into `.github/scripts/*.js`) does this. Draft forces explicit
human ready-flip before any auto-review fires; broken YAML never
lands. docs-sync PRs are also always draft (weekly cadence; a human
flips ready when content warrants review).

## Out of scope for this repo

- Cron, MCP connectors, environment variables, run history — managed in
  the web UI at `claude.ai/code/routines`.
- Per-run secrets — stored in the cloud environment (`env_*`).
