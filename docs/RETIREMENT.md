# Cloud routine retirement — 2026-08-06

The seven cloud routines are retired. `issue-solver` continues unchanged.

## Why

**They stopped working on 2026-07-01 and never resumed.** Every repo-scoped
`api.github.com` call from a cloud session returned HTTP 403 — `sessions are
bound to their configured repositories` / `GitHub access to this repository is
not enabled for this session`. `gh api user` kept succeeding, so the token was
never the problem, and replacing it never helped.

The root cause was never established. Several sessions asserted one and were
wrong each time, so this document does not offer another. What is established:
the failure sits in the session-to-repository binding layer of the hosting
substrate, not in this repository, and nothing in a prompt or an environment
variable moved it. `/web-setup` was tried and did not fix it.

**Nothing was lost by retiring them.** In five weeks they produced no output and
wrote no state — the drift monitor reported all eight state files missing every
single day from 2026-07-03 to 2026-08-05, 34 identical comments on one issue.
There was no output to preserve and no state to migrate.

**The deploy path had been dead even longer.** Since 2026-05-19 every
`RemoteTrigger` call returned `Unable to resolve organization UUID`, verified
across two token rotations. Deploys ran only when a human invoked the deploy
skill by hand.

Full outage taxonomy: [CLOUD_ROUTINES_AUTH.md](CLOUD_ROUTINES_AUTH.md).

## Where each routine's content went

The prompt bodies live in `dryvist/ai-llm-prompts` under `automation/`, now at
`status: retired`. Each carries a `source_history` note naming its destination.
Nothing was deleted; the catalog is the history.

**`estate-briefing`** — the daily briefing was already duplicated by the Hermes
`github-triage` and daily-summary jobs. The weekly weighted scorecard moved to
the Hermes `repo-scorecard` job, with delta history in a memory key instead of a
state repo.

**`bot-pr-merge`** — Phase A (alert triage, labeling, escalation) moved to the
Hermes `bot-pr-triage` job. Phase B (squash-merging) was dropped: the org
Renovate preset already merges bot PRs directly via API, and Hermes never
merges.

**`docs-sync`** — moved to the Hermes `docs-sync` job. Draft-only commits to the
two docs repos are the single code-commit carve-out Hermes has, so it
transferred intact.

**`docs-polish`** — not migrated. It opens PRs against arbitrary repos, which
Hermes will not do. The 8-check README rubric was absorbed into the
`content-guards:validate-readme` skill; fixes are now on demand.

**`repo-audit`** — the `secrets-policy` rule moved to the Hermes
`secrets-policy-audit` job, because it files issues and never PRs, which is what
makes it legal there. `no-scripts` and `claude-md-staleness` were dropped as
already covered by the `script-guards:native-first` and
`claude-md-management:claude-md-improver` skills.

**`estate-janitor`** — nothing salvaged. Branch cleanup, stale-PR sweeps, and
issue triage are covered by the `github-workflows:prune-branches` and `pr-sweep`
skills and the Hermes triage job. The weighted-random task rotation was a
scheduling artifact, not a function.

**`precommit-bump`** — nothing salvaged. Renovate's native `pre-commit` manager
does this. Repos still drifting are repos not yet on the `dryvist/.github`
preset; onboard those instead of re-creating the job.

**`issue-solver`** — kept, unchanged. It never ran on the cloud substrate. It
runs in GitHub Actions on a GitHub App token and has succeeded twice daily
throughout.

## Trigger ids — never reuse

A trigger id is pinned for the life of a routine. These are retired; creating a
new routine with any of them would resurrect a dead identity.

| Routine | Trigger id |
| --- | --- |
| estate-briefing | `trig_01TUW8LMXob53okTF8juhkA8` |
| repo-audit | `trig_01Kaa2rWoVFS4HN4LRR5UMWX` |
| estate-janitor | `trig_01PQsM64nMfQRYptyihRr3Er` |
| precommit-bump | `trig_017wzm9n7a8v2yh3tfAsnmg8` |
| bot-pr-merge | `trig_01N7W9LBApg9veyo2NgdprNV` |
| docs-polish | `trig_01V6C6j9FHn21pk11YfrjURH` |
| docs-sync | `trig_01J9F82aQp1NX5W8PcvSXyh6` |

Previously retired, still never to be reused: The Apothecary
`trig_015zNd6NJRJZCd784qX5FEgm`, The Archivist `trig_01U6EPmvAdUDy2k7LfYWkqts`,
the legacy cloud Issue Solver `trig_01W4LiFv6S6uAf53UoBKrhsX`, Weekly Scorecard
`trig_01TGiH3VuW5Xp7Ej9wSQFvpq`, The Sentinel `trig_012Qm47A...`, The
Distributor `trig_01HoVTrJjo41JFEyzmY1tU5b`.

## What was removed from this repository

- `routines/_common/` — shared fragments and `deploy.config`. The one surviving
  value, the model id, is inlined in `issue-solver.yml`; a single-source file
  with one reader is indirection, not a source of truth.
- `.github/workflows/deploy-routines.yml` — disabled since 2026-05-19.
- `.github/workflows/routine-monitor.yml` — it watched eight dead state files
  and reported `issue-solver` as missing every day while that job ran green, so
  its alarm had stopped carrying information.
- `.claude/skills/deploy-routine-changes/` and the settings hook that nudged
  toward it — there is nothing left to deploy.
- `scripts/render-all-routines.sh` — one prompt renders; `render-check.yml`
  calls `render-routine.sh` directly.

## Operator steps this document does not cover

**Disabling the triggers themselves requires the claude.ai Routines UI.** They
are not reachable from this repository or from any token it holds. If failure
messages are still arriving in Slack, that is why — the prompts never named a
Slack channel, so each run's destination was chosen at runtime, which is what
made the failures appear to scatter across channels.

Verify each disable with a follow-up read. Triggers marked retired in this
estate have twice been found still firing weeks later.

## Verification

- `gh run list --repo dryvist/claude-code-routines` shows `issue-solver` green
  twice daily after this change. This is the regression that matters.
- `scripts/render-routine.sh issue-solver` produces a non-empty prompt with no
  unresolved include markers and no frontmatter.
- No new comments appear on the `[routine-monitor]` tracking issue.
