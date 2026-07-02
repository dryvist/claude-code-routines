# Design History

How these routines came to be, what shaped them,
and lessons learned along the way.

## The Problem (April 2026)

42+ GitHub repos generating constant noise:

- **50+ open PRs** — 80% from Renovate/Dependabot,
  most with green CI, sitting unmerged
- **50+ open issues** — many `[aw]` agentic workflow
  failure reports, stale and self-resolved
- **Stale branches** — merged PRs leaving orphan
  branches across repos
- **~7 dormant repos** — approaching "abandoned"
  territory with no recent commits

A single read-only "GitHub Daily Digest" trigger
posted a summary to Slack each morning. It reported
problems but never fixed anything.

## Inspiration

[githubnext/agentics][agentics] — GitHub's own
collection of agentic workflow examples. Patterns
like `repo-assist` (weighted task rotation),
`issue-arborist` (issue graph management), and
`issue-triage` (classification + labeling) directly
influenced the design.

[agentics]: https://github.com/githubnext/agentics

## Design Session (April 16, 2026)

Five option packages were designed and evaluated:

| # | Name               | Architecture        |
|---| ------------------ | ------------------- |
| 1 | The Custodian      | Single cloud, tasks |
| 2 | The Groundskeeper  | Local-only, disk    |
| 3 | Briefing + Sweep   | Hybrid read/write   |
| 4 | The Issue Arborist | Issue graph focus   |
| 5 | Impression Engine  | Polish + scoring    |

### What Was Chosen: Combination A

All 5 routines — "The Complete Estate" — with zero
scope overlap. Each routine owns a distinct domain.
The Groundskeeper (local branch pruning) was
scoped to local-only tasks, while the other 4
deploy as cloud triggers.

### Key Design Decisions

**Weighted random rotation (Custodian)**:
Instead of doing the same thing every day, The
Custodian picks 2 tasks per run from a pool of 8,
weighted by impact. PR Triage (weight 25) runs
roughly every other day. Inactive Repo Scan
(weight 5) runs about once a week. Date-seeded
randomness ensures reproducible selection and
fair coverage over a ~4-day full rotation.

**Read-only morning, action evening (Briefing)**:
Safety through separation. The Morning Briefing
gives situational awareness with zero mutations.
Actions happen in The Custodian's overnight window
when the human is asleep and can review in the
morning.

**One repo per day (Daily Polish)**:
Deep-cleaning all 42 repos daily would blow the
token budget. Rotating through one per day means
every active repo gets attention within ~2 weeks.
Staleness-based ordering ensures the most neglected
repo goes first.

**Scoring rubric (Weekly Scorecard)**:
Seven factors weighted by visitor impact: README
quality (25%), commit recency (20%), open issues
(15%), CI status (15%), releases (10%), description
(10%), license (5%). Week-over-week deltas create
accountability and surface trends.

**Sonnet over Opus**:
Routines are mechanical, not architectural. They
follow explicit rules, not open-ended reasoning.
Sonnet at ~$0.36/day total (~$10.80/month) vs
Opus at ~$3.60/day ($108/month) — 10x savings
with no quality impact for this workload.

**Safety caps on every routine**:
Max 8 PR merges, 10 issue closures, 3 issue
creations, 15 branch deletions per Custodian run.
Daily Polish creates draft PRs only — never
auto-merges. Morning Briefing and Weekly Scorecard
are strictly read-only. Comment deduplication
prevents bot spam (check for existing comments
within 7 days before posting).

## The Overnight Failure (April 17, 2026)

All 4 cloud routines failed on their first
scheduled run.

**Root cause**: Every prompt relied on `gh` CLI
commands, but `gh` is not pre-installed in
Anthropic's cloud sandbox. The design session ran
locally where `gh` works, so this was never caught.

### Investigation Path

1. **GitHub MCP Connector** — explored using the
   built-in GitHub MCP server
   (`api.githubcopilot.com/mcp`). Found gaps: no
   branch deletion, no repo description updates,
   limited search capabilities. Rewriting all 4
   prompts for MCP tools was high-risk.

2. **Official docs** — the answer was simple: add
   `apt update && apt install -y gh` to the
   environment setup script (cached after first
   run) and set `GH_TOKEN` as an environment
   variable. `gh` reads it automatically.

### Signed Commits

Daily Polish creates draft PRs with file changes.
In the cloud sandbox there is no local git identity,
so `git commit` would produce unsigned commits.
The fix: use the GitHub Contents API
(`gh api repos/.../contents/...`) to create commits
server-side, signed by GitHub's web-flow key. This
satisfies branch protection rules requiring signed
commits.

### The Fix

All 4 triggers share one cloud environment. One
environment configuration change fixed all four:

1. Setup script: `apt update && apt install -y gh`
2. Environment variable: `GH_TOKEN=<PAT>`
3. Added `## Prerequisites` section to each prompt
4. Rewrote Daily Polish commit workflow for
   API-signed commits

## Token Monitoring

Estimated daily cost: ~$0.36 (Sonnet pricing).
A review checkpoint was set for April 23, 2026
(7 days post-deployment) to validate actual costs
and trim if excessive.

## Issue Solver Addendum (April 25, 2026)

The original 4 routines covered repo hygiene
(Polish), maintenance rotation (Custodian),
situational awareness (Briefing), and portfolio
scoring (Scorecard). What was missing: a routine
that actually moves *issues* toward done, not just
labels and reports them.

Issue Solver was added as a fifth routine, cloned
from Daily Polish to inherit its conservative
posture (DRAFT PRs, signed commits, hard caps,
mandatory Slack output). The clone happened only
after fixing two latent defects in Polish that
would otherwise have propagated.

### Defects fixed in Polish before cloning

1. **Unsigned-commit fallback** — Polish previously
   listed `Write` and `Edit` in `allowed_tools`,
   which let the agent fall back to local
   `git commit` when API calls felt awkward. Local
   commits in the sandbox are unsigned and fail
   branch protection (PR #138 on `tf-splunk-aws`
   wedged because of this). Removing those tools
   forces Contents-API-only commits. A "Hard Rules"
   section was added at the top of the prompt to
   make the constraint load-bearing.

2. **Broken session URL placeholder** — the PR body
   referenced `${CLAUDE_CODE_REMOTE_SESSION_ID}`,
   which doesn't exist in the runtime. PRs rendered
   the literal placeholder string. Replaced with a
   static link to the prompt source on GitHub.

### Issue Solver design choices

**Two-phase gate (cheap triage → expensive
implementation)**: Inspired by Metabase's
Repro-Bot. Sonnet runs a ~2k-token triage on the
top 5 candidates and outputs structured JSON
(solvable, complexity, estimated_files, risks).
Only candidates that pass the gate proceed to the
Investigate/Implement/Verify phases. Triage is
dirt cheap relative to a wrong implementation.

**No opt-in label** (user choice). Unlike gh-aw's
`issue-monster` which gates on a `cookie` label,
Issue Solver auto-attempts any open issue meeting
score and complexity thresholds. This raises the
safety bar elsewhere: tighter triage thresholds
(`complexity ∈ {trivial, small}` by default,
`medium` only with empty risks AND ≤ 3 files),
strict scope filters in Hard Rules (no infra, no
workflow, no dependency files unless explicitly
labeled), and a pre-flight secret-pattern scan
before each Contents API PUT.

**State gist for fresh issues** (mirrors Polish's
rotation gist). Each attempt writes
`{repo, issue, date, outcome}` to a separate
gist. The next run filters out any
`(repo, number)` seen within the last 7 days,
guaranteeing a fresh issue every run. Outcomes
other than `drafted_pr` are eligible for retry
after the cooldown — abandoned-for-CI-failure
might be solvable later if the upstream
flakiness clears.

**Twice-daily cadence**. Morning run (7am CT)
catches issues opened overnight; evening run
(7pm CT) catches issues opened during the
workday. Slotted between Custodian (2 AM) and
Polish (11 PM) so the five routines never overlap.

**Pre-compute filtering in deterministic layer**
(stolen from gh-aw issue-monster). The
`gh search issues` + `jq` scoring pipeline runs
in shell with zero LLM tokens. The agent only
chooses among 5 pre-ranked candidates, never
reads 50 issues directly. Scoring rubric:
+50 bug, +40 good-first-issue, +35
enhancement, +30 documentation; −40 for
wontfix/blocked/needs-* labels; +20 for recency
(opened in last 7 days); +10 per thumbs-up
(capped); −100 cooldown penalty for issues in
the state gist within 7 days.

**Mandatory Slack output, four exit paths**:
A (drafted PR), B (triage rejected all), C (no
candidates surfaced), D (abandoned mid-flight
with issue comment). Polish's noop path was also
added as part of this work (1C in the
improvement plan) so both routines share the
same "always emit something" discipline.

## The Solver — Linear-only scope (July 1, 2026)

The Solver's GitHub-Issue fallback (Phase 1b, gated on the
`ai-ready` label) was removed. The Solver now works a single
queue: **Linear (JAC team)**. If Linear yields no work, it
exits — it no longer looks at GitHub issues.

Why: the GitHub issue → PR path is owned by `dryvist/ai-workflows`.
Its `cc-issue-resolver` resolves issues event-driven on the
`ai:ready` label (applied by `issue-triage`, and by the new
`issue-backlog-sweep` for pre-existing backlog). Keeping a second,
cron-driven system that also pulled GitHub issues risked two
systems opening rival PRs for the same issue — wasted tokens and
merge conflicts. Splitting cleanly by source removes that race:

- **GitHub issues → ai-workflows** (`cc-issue-resolver`, event-driven).
- **Linear tasks → The Solver** (cron, this repo).

Sections above that describe the Solver triaging GitHub issues
(the April 25 addendum's `gh search issues` scoring pipeline,
"state gist for fresh issues," twice-daily "catch issues opened
overnight") are retained as design history but no longer reflect
the routine — those mechanisms applied to the removed GH queue.
The twice-daily cadence and Linear discovery/triage/implement
pipeline remain.

## What's Not Here

**The Groundskeeper** (Option 2) runs as a local
`/schedule` cron, not a cloud trigger. It handles
local branch pruning and worktree health checks —
tasks that require filesystem access. It is not
included in this repo because it runs locally and
its prompt lives in the local schedule
configuration.
