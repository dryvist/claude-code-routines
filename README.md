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
`SENTINEL_OPERATOR_PATTERNS` is an optional denylist
of extra regexes The Sentinel flags as operator-specific.

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

[`.github/workflows/deploy-routines.yml`][dw]
runs `anthropics/claude-code-action@v1` against
Anthropic's `RemoteTrigger` API, authenticated
with `CLAUDE_CODE_OAUTH_TOKEN`. It triggers on
`workflow_dispatch` and daily at 06:00 UTC.

After merging a prompt change to `main`, deploy
immediately with `gh workflow run deploy-routines.yml --ref main`.

The workflow's instructions live alongside it in
[`deploy-routines.prompt.md`][dpr].

See [CLAUDE.md](CLAUDE.md) for the full operator
guide, the manual `/schedule update` fallback, and
the hard rules every routine prompt must follow.

[dw]: .github/workflows/deploy-routines.yml
[dpr]: .github/workflows/prompts/deploy-routines.prompt.md

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
