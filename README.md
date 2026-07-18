# claude-code-routines

Version-controlled deployment metadata and pinned prompts for
[Claude Code Routines][routines] — scheduled agents
that manage a GitHub portfolio. The routine prompts
are owner-agnostic; the operator sets `$GH_OWNER`
and a few related
env vars (see
[`docs/CLOUD_ROUTINES_AUTH.md`](docs/CLOUD_ROUTINES_AUTH.md)).

See [DESIGN.md](DESIGN.md) for the origin story,
design decisions, and lessons learned.

[routines]: https://docs.anthropic.com/en/docs/claude-code/routines

## Routines

Canonical registry — one row per live trigger, sorted by cron time.
`trigger_id`s and schedules are pinned in `routines/registry.yaml`.

| Routine                  | Cron (UTC)       | Purpose                        |
| ------------------------ | ---------------- | ------------------------------ |
| [docs-polish][dp]        | `0 4 * * *`      | Fix worst-scoring repo's docs  |
| [repo-audit][ra]         | `0 6 * * *`      | 3-rule audit → 1 PR or issue   |
| [estate-janitor][ej]     | `0 7 * * *`      | Weighted-random maintenance    |
| [precommit-bump][pb]     | `0 8 * * *`      | pre-commit pin bumps (≤3 PRs)  |
| [docs-sync][ds]          | `13 8 * * 1`     | Weekly documentation PRs (0–2) |
| [estate-briefing][eb]    | `0 10 * * *`     | Daily brief + Mon scorecard    |
| [bot-pr-merge][bm]       | `15 11,17 * * *` | Security triage + bot merges   |
| [issue-solver][is] (GHA) | `0 0,12 * * *`   | Solve one Linear task → 1 PR   |

Names are functional kebab-case tokens used identically as file
basename, attribution tag, state file, and Slack header — see the
naming convention and rename ledger in
[AGENTS.md](AGENTS.md#naming-convention-2026-07-consolidation).

issue-solver runs as a GitHub Actions workflow
(`.github/workflows/issue-solver.yml`), not a cloud routine — its
registry entry has no `trigger_id`.

[dp]: vendor/ai-llm-prompts/automation/routine-docs-polish.md
[ra]: vendor/ai-llm-prompts/automation/routine-repo-audit.md
[ej]: vendor/ai-llm-prompts/automation/routine-estate-janitor.md
[pb]: vendor/ai-llm-prompts/automation/routine-precommit-bump.md
[ds]: vendor/ai-llm-prompts/automation/routine-docs-sync.md
[eb]: vendor/ai-llm-prompts/automation/routine-estate-briefing.md
[bm]: vendor/ai-llm-prompts/automation/routine-bot-pr-merge.md
[is]: vendor/ai-llm-prompts/automation/routine-issue-solver.md

Retired/merged triggers (disabled in the cloud, no source file):
The Apothecary merged into bot-pr-merge and The Archivist into
docs-polish/estate-briefing (2026-07-02); Morning Briefing and the
original Weekly Scorecard merged into estate-briefing; the resurrected
Weekly Scorecard and The Sentinel retired 2026-07-01; The Distributor
replaced by org Required Workflows. See
[AGENTS.md](AGENTS.md#retired-routines).

## Architecture

All cloud routines share a single Claude Code cloud
environment and post results to Slack via MCP. A scheduled GHA
monitor ([`routine-monitor.yml`](.github/workflows/routine-monitor.yml))
cross-checks each routine's `prompt_sha256` fingerprint and
state-file freshness daily, maintaining a single drift/liveness
tracking issue in this repo.

```text
┌─────────────┐   ┌────────────────┐   ┌───────┐
│ Cron Trigger │──▶│ Cloud Sandbox  │──▶│ Slack │
│  (Anthropic) │   │ gh + GH_TOKEN  │   │  MCP  │
└─────────────┘   └────────────────┘   └───────┘
                          │
                          ▼
                  ┌──────────────┐
                  │  GitHub API  │
                  └──────────────┘
```

## Installation

Claude Code cloud routines run in a shared environment.
Configure it at [claude.ai/code](https://claude.ai/code)
under environment settings.

```bash
# 1. Install gh CLI in the cloud sandbox (cached after first run)
apt update && apt install -y gh

# 2. Set GH_TOKEN as an environment variable in the trigger config
export GH_TOKEN=<your GitHub PAT>
```

### Setup Script

```bash
apt update && apt install -y gh
```

The result is cached after the first run —
`gh` is instantly available on subsequent sessions.

### Environment Variables

```text
GH_TOKEN=<fine-grained PAT, resource owner dryvist (see PAT scopes below)>
GH_OWNER=<single owner/org for all routines, e.g. dryvist>
STATE_REPO=<cross-run state repo, e.g. dryvist/routine-state>
```

`gh` reads `GH_TOKEN` automatically. Every routine scopes
its work to the singular `GH_OWNER` (one org/user) — no
routine enumerates a multi-owner list. Cross-run state lives as
JSON files on the `data` branch of the private `STATE_REPO`
(under `dryvist`), written via the Contents API — cloud routines
cannot use gists (the egress proxy blocks gist writes), and the
org ruleset makes `main` PR-only so state uses `data`.

### Routine registration (cloud-hosted routines only)

Cloud routines are kept in sync by Claude itself during editing
sessions in this repo — the GHA deploy workflow is currently
disabled (see [Deploying Changes](#deploying-changes) below).
The procedure lives in
[`.claude/skills/deploy-routine-changes/SKILL.md`][skill]. A
repo-level hook in `.claude/settings.json` reminds Claude to
invoke the skill whenever the catalog gitlink or `routines/registry.yaml` is
edited. For new routines, the skill opens a small follow-up PR to back-commit
the issued `trigger_id`.

Cloud routines vs. GHA-managed prompts are distinguished by the
presence of a `cron` field in the registry; entries without
`cron` (for example `issue-solver`) run via their own native
workflows and are not touched by the skill.

Env vars and MCP connections still need a one-time setting in the
shared cloud env at
[`claude.ai/code/routines`](https://claude.ai/code/routines) —
those values are secrets and live outside the repo.

[skill]: .claude/skills/deploy-routine-changes/SKILL.md

### Required PAT Scopes

The runtime token is a fine-grained PAT with **resource owner
`$GH_OWNER` (`dryvist`)** and write access to the operational repos
the routines touch **and** to `$STATE_REPO`. The classic-scope
equivalents are:

| Scope             | Used By                                     |
| ----------------- | ------------------------------------------- |
| `repo`            | All routines — read/write repo + state      |
| `delete_repo`     | estate-janitor — branch deletion via API    |
| `workflow`        | estate-janitor — workflow run checks        |
| `read:org`        | All routines — org-level search             |
| `project`         | estate-briefing — Monday scorecard queries  |
| `security_events` | bot-pr-merge — CodeQL/Dependabot alert read |

No `gist` scope: cloud routines cannot write gists (egress proxy
blocks them); all state is in `$STATE_REPO` via the Contents API.

### MCP Connections

Each routine connects to Slack for output:

- **Name**: `Slack`
- **URL**: `https://mcp.slack.com/mcp`

## Usage

Once the shared cloud environment is configured, the routines run
themselves — no manual invocation. Each trigger fires on its cron
schedule (see the [Routines](#routines) table), scopes its work to
the single `$GH_OWNER`, performs its task against the GitHub API, and
posts a summary to Slack. issue-solver runs on its own GitHub Actions
schedule instead of a cloud trigger.

To change behaviour, release the relevant central catalog prompt, advance the
pinned gitlink, and let the deploy path re-sync the cloud trigger (see
[Deploying Changes](#deploying-changes)). To add a routine, add its central
prompt and a local registry entry with a unique cron, then deploy; registration
back-commits the issued `trigger_id`.

## Deploying Changes

The GHA-based deploy at [`.github/workflows/deploy-routines.yml`][dw]
is **currently disabled**. The `CLAUDE_CODE_OAUTH_TOKEN` it injects
into `anthropics/claude-code-action@v1` does not carry the org
binding the Anthropic Routines API needs — every `RemoteTrigger`
call returned `Unable to resolve organization UUID`, verified
2026-05-19 across two consecutive token rotations. The workflow
header has the full diagnosis and re-enablement instructions.

While that's upstream-blocked, the active deploy path is
[`.claude/skills/deploy-routine-changes/SKILL.md`][skill] —
Claude invokes it during an editing session in this repo (the
interactive harness has working RemoteTrigger access). A
repo-level hook nudges Claude to run the skill whenever the catalog pin or
local registry is touched.

For background and the manual `/schedule update` last-resort
fallback, see [CLAUDE.md](CLAUDE.md).

[dw]: .github/workflows/deploy-routines.yml

### Prompt assembly (DRY partials)

The immutable Git submodule `vendor/ai-llm-prompts` owns routine prompt
bodies and flattened fragments. `routines/registry.yaml` owns deployment
metadata. `scripts/render-routine.sh <basename>` strips OKF frontmatter
and expands every `routine-fragment-*.md` marker before deployment.
The render check builds all eight prompt bodies in CI.

## File Structure

```text
claude-code-routines/
├── .gitmodules
├── AGENTS.md
├── README.md
├── .claude/
│   ├── settings.json
│   └── skills/deploy-routine-changes/SKILL.md
├── .github/workflows/
│   ├── deploy-routines.yml
│   ├── issue-solver.yml
│   ├── render-check.yml
│   └── routine-monitor.yml
├── routines/
│   ├── registry.yaml
│   └── _common/deploy.config
├── scripts/
│   ├── render-routine.sh
│   └── render-all-routines.sh
└── vendor/ai-llm-prompts
```

## License

MIT

---

> Part of a [larger ecosystem of ~40 repos](https://docs.jacobpevans.com) —
> see how it all fits together.
