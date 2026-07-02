# claude-code-routines

Version-controlled prompt files for
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
`trigger_id`s are pinned in each file's YAML frontmatter.

| Routine                 | Cron (UTC)       | Purpose                         |
| ----------------------- | ---------------- | ------------------------------- |
| [Daily Polish][dp]      | `0 4 * * *`      | Deep-clean one repo per day     |
| [The Inspector][in]     | `0 6 * * *`      | 3-rule audit → 1 PR or issue    |
| [The Custodian][cu]     | `0 7 * * *`      | Weighted-random maintenance     |
| [The Quartermaster][qm] | `0 8 * * *`      | pre-commit pin bumps (≤3 PRs)   |
| [Docs Sync][ds]         | `13 8 * * 1`     | Weekly documentation PRs        |
| [The Archivist][ar]     | `0 9 * * *`      | README quality / docs coverage  |
| [The Observer][ob]      | `0 10 * * *`     | Daily briefing + Mon repo score |
| [The Conductor][co]     | `15 11,17 * * *` | Bot-PR allowlist merges         |
| [The Apothecary][ap]    | `0 13 * * *`     | Security alert triage + labels  |
| [The Solver][is] (GHA)  | `0 0,12 * * *`   | Solve one task → 1 ready PR     |

The Solver runs as a GitHub Actions workflow
(`.github/workflows/issue-solver.yml`), not a cloud routine — its
prompt file has no `trigger_id`.

[dp]: routines/daily-polish.prompt.md
[in]: routines/inspector.prompt.md
[cu]: routines/custodian.prompt.md
[qm]: routines/quartermaster.prompt.md
[ds]: routines/docs-sync.prompt.md
[ar]: routines/archivist.prompt.md
[ob]: routines/observer.prompt.md
[co]: routines/conductor.prompt.md
[ap]: routines/apothecary.prompt.md
[is]: routines/issue-solver.prompt.md

Retired triggers (disabled in the cloud, no source file): Morning
Briefing and the original Weekly Scorecard merged into The Observer;
the resurrected Weekly Scorecard (Estate Consolidation reporting) and
The Sentinel retired 2026-07-01; The Distributor replaced by org
Required Workflows. See [AGENTS.md](AGENTS.md#retired-routines).

## Architecture

All cloud routines share a single Claude Code cloud
environment and post results to Slack via MCP.

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
invoke the skill whenever a `routines/*.prompt.md` file is
edited. For new routines, the skill opens a small follow-up PR to
back-commit the issued `trigger_id`.

Cloud routines vs. GHA-managed prompts are distinguished by the
presence of a `cron` field in YAML frontmatter; prompts without
`cron` (e.g. `issue-solver.prompt.md`) run via their own native
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

| Scope         | Used By                                |
| ------------- | -------------------------------------- |
| `repo`        | All routines — read/write repo + state |
| `delete_repo` | Custodian — branch deletion via API    |
| `workflow`    | Custodian — workflow run checks        |
| `read:org`    | All routines — org-level search        |
| `project`     | Observer — Monday scorecard queries    |

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
posts a summary to Slack. The Solver runs on its own GitHub Actions
schedule instead of a cloud trigger.

To change behaviour, edit the relevant `routines/*.prompt.md` file and
let the deploy path re-sync the cloud trigger (see
[Deploying Changes](#deploying-changes)). To add a routine, copy an
existing prompt file, give it a unique `cron` value in the YAML
frontmatter, and deploy — registration issues and back-commits the new
`trigger_id`.

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
repo-level hook nudges Claude to run the skill whenever a
`routines/*.prompt.md` file is touched.

For background and the manual `/schedule update` last-resort
fallback, see [CLAUDE.md](CLAUDE.md).

[dw]: .github/workflows/deploy-routines.yml

### Prompt assembly (DRY partials)

Routine files in `routines/` are the DRY source form. Shared
boilerplate (hard rules, connectivity preflight, state-file
convention, attribution, Slack sanitization) lives in
`routines/_common/` partials, pulled in by marker lines of the form
`<!-- include: _common/<name>.md -->`.

The deployed prompt is always the **rendered** output of
`scripts/render-routine.sh <routine-path>`, which expands every
marker (and fails on unresolvable or nested includes). The
deploy skill renders before each RemoteTrigger call, and the
[render-check workflow](.github/workflows/render-check.yml)
renders every prompt in CI, uploading the blobs as an artifact.
See [AGENTS.md](AGENTS.md) for the full mechanism.

## File Structure

```text
claude-code-routines/
├── README.md
├── CLAUDE.md
├── AGENTS.md
├── DESIGN.md
├── docs/
│   ├── CLOUD_ROUTINES_AUTH.md
│   └── DISTRIBUTOR_RETIREMENT.md
├── .claude/
│   ├── settings.json
│   └── skills/deploy-routine-changes/SKILL.md
├── .github/
│   ├── CODEOWNERS
│   └── workflows/
│       ├── deploy-routines.yml        # disabled (see header)
│       ├── issue-solver.yml           # The Solver (GHA)
│       └── prompts/
│           └── deploy-routines.prompt.md
└── routines/
    ├── .markdownlint.yaml
    ├── apothecary.prompt.md
    ├── archivist.prompt.md
    ├── conductor.prompt.md
    ├── custodian.prompt.md
    ├── daily-polish.prompt.md
    ├── docs-sync.prompt.md
    ├── inspector.prompt.md
    ├── issue-solver.prompt.md
    ├── observer.prompt.md
    └── quartermaster.prompt.md
```

## License

MIT

---

> Part of a [larger ecosystem of ~40 repos](https://docs.jacobpevans.com) —
> see how it all fits together.
