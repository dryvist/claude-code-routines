# claude-code-routines

Version-controlled prompt files for
[Claude Code Routines][routines] — scheduled agents
that manage a GitHub portfolio. The routine prompts
are owner-agnostic; the operator sets `$GH_OWNER`
(or `$GH_OWNERS` for The Sentinel) and a few related
env vars (see
[`docs/CLOUD_ROUTINES_AUTH.md`](docs/CLOUD_ROUTINES_AUTH.md)).

See [DESIGN.md](DESIGN.md) for the origin story,
design decisions, and lessons learned.

[routines]: https://docs.anthropic.com/en/docs/claude-code/routines

## Routines

| Routine                | Schedule           | Purpose                       |
| ---------------------- | ------------------ | ----------------------------- |
| [Morning Briefing][mb] | Daily 5:00 AM CT   | Read-only activity summary    |
| [The Sentinel][se]     | Daily 12:33 AM CT  | Param/secret audit + 1 PR     |
| [The Custodian][cu]    | Daily 2:00 AM CT   | Weighted-random maintenance   |
| [Issue Solver][is]     | Daily 7am + 7pm CT | Solve one issue → draft PR    |
| [Daily Polish][dp]     | Daily 11:00 PM CT  | Deep-clean one repo per day   |
| [Weekly Scorecard][ws] | Mondays 5:00 AM CT | Portfolio health scores       |

[mb]: routines/morning-briefing.prompt.md
[se]: routines/sentinel.prompt.md
[cu]: routines/custodian.prompt.md
[is]: routines/issue-solver.prompt.md
[dp]: routines/daily-polish.prompt.md
[ws]: routines/weekly-scorecard.prompt.md

## Architecture

All 6 routines share a single Claude Code cloud
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
GH_TOKEN=<your GitHub PAT>
GH_OWNER=<single owner for most routines>
GH_OWNERS=<comma-separated list, Sentinel only>
SENTINEL_OPERATOR_PATTERNS=<optional, comma-separated regex list>
```

`gh` reads `GH_TOKEN` automatically. `GH_OWNERS` (e.g.
`user-a,org-b`) is consumed only by The Sentinel —
existing routines keep using the singular `GH_OWNER`.
`SENTINEL_OPERATOR_PATTERNS` is an optional list of
additional regexes The Sentinel flags as operator-specific
findings (e.g. internal hostnames, project codenames).

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

| Scope         | Used By                                |
| ------------- | -------------------------------------- |
| `repo`        | All routines — read/write repo data    |
| `delete_repo` | Custodian — branch deletion via API    |
| `gist`        | Polish, Solver, Scorecard, Sentinel    |
| `workflow`    | Custodian — workflow run checks        |
| `read:org`    | All routines — org-level search        |
| `project`     | Morning Briefing — project queries     |

### MCP Connections

Each routine connects to Slack for output:

- **Name**: `Slack`
- **URL**: `https://mcp.slack.com/mcp`

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

## File Structure

```text
claude-code-routines/
├── README.md
├── CLAUDE.md
├── DESIGN.md
├── docs/
│   └── CLOUD_ROUTINES_AUTH.md
├── .gitignore
├── .markdownlint-cli2.yaml
├── .readme-validator.yaml
├── .github/
│   └── workflows/
│       ├── deploy-routines.yml
│       └── prompts/
│           └── deploy-routines.prompt.md
└── routines/
    ├── .markdownlint.yaml
    ├── custodian.prompt.md
    ├── daily-polish.prompt.md
    ├── issue-solver.prompt.md
    ├── morning-briefing.prompt.md
    ├── sentinel.prompt.md
    └── weekly-scorecard.prompt.md
```

## License

MIT
