# claude-code-routines

Home of `issue-solver`: a scheduled GitHub Actions workflow that picks one
Linear task and opens one ready-for-review pull request that closes it.

The seven cloud routines this repo used to run were retired on 2026-08-06 with
the hosting substrate they ran on. [`docs/RETIREMENT.md`](docs/RETIREMENT.md)
records why, where each prompt's content went, and which trigger ids must never
be reused. [DESIGN.md](DESIGN.md) keeps the origin story and the lessons.

## The one routine

| Routine | Schedule (UTC) | Purpose |
| --- | --- | --- |
| [issue-solver][is] | `0 0,12 * * *` | Solve one Linear task, open one PR |

[is]: vendor/ai-llm-prompts/automation/issue-solver.md

It runs in GitHub Actions on a GitHub App installation token. It never touched
the cloud-routine substrate, which is why it kept working through the outage
that ended the others. `workflow_dispatch` is enabled, so you can run it on
demand without waiting for the cron.

## How it fits together

```text
dryvist/ai-llm-prompts            the prompt body lives here
  automation/issue-solver.md
        |
        |  pinned as a submodule
        v
vendor/ai-llm-prompts             this repo's pinned copy
        |
        |  scripts/render-routine.sh issue-solver
        v
.rendered-issue-solver.md         frontmatter stripped, includes expanded
        |
        v
.github/workflows/issue-solver.yml
```

This repo owns the consumer half only — the schedule, the token, the model, and
the allowed-tools list. The prompt text belongs to the catalog. Changing what
the routine *says* is a catalog change; changing when or how it *runs* is a
change here.

### Files that matter

- `routines/registry.yaml` — the pinned catalog commit and the prompt filename.
- `scripts/render-routine.sh` — strips OKF frontmatter, expands
  `<!-- include: fragment-<name>.md -->` markers.
- `.github/workflows/issue-solver.yml` — the scheduled run.
- `.github/workflows/render-check.yml` — proves the render still works, so a
  broken prompt fails in CI rather than at 00:00 UTC.

## Installation

Clone with the submodule — without it there is no prompt to render:

```bash
git clone --recurse-submodules git@github.com:dryvist/claude-code-routines.git
cd claude-code-routines
scripts/render-routine.sh issue-solver   # prints the rendered prompt
```

An existing clone that predates the submodule needs
`git submodule update --init vendor/ai-llm-prompts`.

Running the workflow needs four values on the repository. The App token is
minted per run and scoped to the permissions that run actually uses; there is
no long-lived PAT.

| Name | Kind | Purpose |
| --- | --- | --- |
| `GH_APP_CLAUDE_BOT_ID` | variable | App id for the token |
| `GH_APP_CLAUDE_BOT_PRIVATE_KEY` | secret | Signing key for that App |
| `CLAUDE_CODE_OAUTH_TOKEN` | secret | Authenticates the run to Anthropic |
| `LINEAR_API_KEY` | secret | Reads the task queue |

With `LINEAR_API_KEY` unset the run reports a configuration gap and exits. It
does not fall back to GitHub issues — that path belongs to `ai-workflows`.

## Usage

The workflow runs itself twice daily. Two things you do by hand:

**Run it now** instead of waiting for the cron:

```bash
gh workflow run issue-solver.yml --repo dryvist/claude-code-routines
gh run watch --repo dryvist/claude-code-routines
```

**Change what it says.** The prompt text belongs to the catalog, so:

1. Open a PR against `dryvist/ai-llm-prompts` changing
   `automation/issue-solver.md`.
2. After it merges, advance the `vendor/ai-llm-prompts` submodule **and** the
   `catalog.commit` field in `routines/registry.yaml` to the same commit.
   Moving one without the other makes the registry lie about what renders.
3. Confirm `render-check` passes, then dispatch a run rather than waiting.
