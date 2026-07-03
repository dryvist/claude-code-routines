# Cloud Routines — Authentication & Identity

> **Note (2026-05-19):** the GHA-based deploy described below is
> currently disabled — see `.github/workflows/deploy-routines.yml` for
> the diagnosis. While that's upstream-blocked, the active deploy path
> is the project skill at
> `.claude/skills/deploy-routine-changes/SKILL.md`. The env-var setup
> below is still correct (the routines themselves run fine; only the
> deploy *mechanism* changed).

Operator runbook for getting a fork of this repo running against your own
GitHub org. The routines themselves are written to be account-agnostic —
all account-specific values come from routine env vars listed below.

> **This deployment (dryvist), as of 2026-07-02:** the runtime token is a
> fine-grained PAT with **resource owner `dryvist` (`$GH_OWNER`)** and write
> access to the operational repos **and** to the private state repo
> `$STATE_REPO` (`dryvist/routine-state`). Commit identity comes from the
> `GIT_COMMITTER_*` env via the Contents API `committer` object. State is JSON
> files on the **`data` branch** of `$STATE_REPO` (`state/<routine>.json` +
> `pr-budget.json`) — **not `main`**: the org ruleset makes `main` PR-only, and
> the `data` branch only requires verified signatures (which the Contents API's
> web-flow signing provides). **Cloud routines cannot use gists** — the egress
> proxy blocks gist writes (`"Gist writes are not permitted through this
> proxy"`, HTTP 403). The account-agnostic App-bot runbook below still works for
> a fresh fork; the App-vs-PAT choice only changes `author.login` on commits.

## Architecture summary

- **Identity**: a GitHub App you create and install on the repos the
  routines should mutate. The App's bot user (`<app-slug>[bot]`)
  becomes the `author.login` on every commit landed via the Contents
  API.
- **Auth**: a long-lived fine-grained PAT scoped to those repos.
  `gh` reads it from `GH_TOKEN` in the routine env. Cloud sandboxes
  can't refresh secrets at runtime, so installation tokens (1h
  lifetime) aren't viable here — a 1-year PAT is.
- **Signing**: GitHub web-flow. Every commit landed via
  `gh api .../contents/...` is signed automatically by GitHub; no GPG
  or SSH key needed in the sandbox.

## One-time setup

### 1. Create the GitHub App

`https://github.com/settings/apps/new` → name it whatever you want
(slug becomes `<your-app-slug>`). Permissions:

- Contents: Read and write
- Pull requests: Read and write
- Issues: Read and write (estate-janitor needs this for label edits
  and the repo-health audit issue it creates)
- Metadata: Read-only

Install on either your personal account or your org. Note the numeric
**App ID** from the settings page — you'll need it for the no-reply
email format.

### 2. Mint the runtime PAT

`https://github.com/settings/tokens?type=beta`:

- Resource owner: the account that owns the App
- Repository access: All repositories the routines should touch
- Permissions: same as the App (Contents/PRs/Issues RW, Metadata R)
- Expiry: 1 year (max GitHub allows for fine-grained PATs)

Store the resulting token wherever you keep secrets (Doppler, Vault,
1Password, AWS Secrets Manager, GitHub repo secret — your call). Plan
to rotate annually.

### 3. Set the routine env

At <https://claude.ai/code/routines>, on the env shared by all cloud
routines:

- `GH_TOKEN` — the runtime PAT from step 2. Must also have write access to
  the state repo below (mint it for the operational repos **plus**
  `$STATE_REPO`).
- `GH_OWNER` — the org or user that owns the target repos
  (e.g. `acme-corp`).
- `STATE_REPO` — `owner/repo` of the private cross-run state store
  (e.g. `dryvist/routine-state`). Before first run, create it as a private repo
  under `$GH_OWNER` **and create a `data` branch** — routines write state to
  `data` (the org ruleset makes `main` PR-only). Routines create
  `state/<routine>.json` and `pr-budget.json` on `data` on demand.
- `GIT_AUTHOR_NAME` — `<your-app-slug>[bot]` (matches what GitHub
  renders for App-attributed commits).
- `GIT_AUTHOR_EMAIL` — the App's no-reply form, lowercase slug:
  `<APP_ID>+<your-app-slug>[bot]@users.noreply.github.com`.
- `GIT_COMMITTER_NAME` — same value as `GIT_AUTHOR_NAME`.
- `GIT_COMMITTER_EMAIL` — same value as `GIT_AUTHOR_EMAIL`.
- `PROMPT_SOURCE_URL` — URL of the prompt file in your fork
  (referenced in generated PR bodies).

`<APP_ID>` is the numeric ID on the App's settings page; the slug is
the lowercase form of the App name. Find them once via
`gh api /apps/<your-app-slug>` after a JWT-authenticated test, or
just create one test commit and read the resulting `author.email`.

### 4. Verify

Trigger any routine (docs-polish is cheapest) and inspect the resulting
PR's commits:

```bash
gh api repos/$GH_OWNER/<recently-mutated-repo>/pulls/<N>/commits \
  --jq '.[] | {login: .author.login, verified: .commit.verification.verified}'
```

Expect `login: "<your-app-slug>[bot]"` and `verified: true` on every
entry. If `login` is your own GitHub username instead, the
`committer.*` overrides aren't reaching the API — check that
`GIT_COMMITTER_NAME` / `GIT_COMMITTER_EMAIL` are set on the routine env
(not just locally) and that the routine prompts use the
`jq | gh api --input -` pattern (flat `-f committer.name=...` is
silently dropped).

## Annual PAT rotation

```bash
# 1. Mint replacement at https://github.com/settings/tokens?type=beta
#    (same scopes as before; 1-year expiry).

# 2. Update wherever you store secrets, e.g. Doppler:
doppler secrets set CLAUDE_ROUTINES_PAT='<new-token>' \
  -p <your-project> -c <your-config>

# 3. Re-paste GH_TOKEN into the Anthropic shared routine env at
#    https://claude.ai/code/routines (web UI; no API).

# 4. Verify a routine still produces signed bot commits using the
#    command from step 4 above.

# 5. Revoke the old PAT at https://github.com/settings/tokens.
```

## Compromise response

PAT leaked → revoke at `https://github.com/settings/tokens`, mint
replacement, run rotation above.

App private key leaked → regenerate at
`https://github.com/settings/apps/<your-app-slug>`, push the new key
to your secret store. App credentials don't currently flow into the
routine env (only the PAT does), so the routine env doesn't need
re-pasting unless you rotate the PAT at the same time.

## Outage recovery

When routines post `🔴 FATAL` (or a run returns no data), the connectivity
preflight (`_common/preflight.md`) has already classified the failure. Diagnose
in this order — each layer is independent:

1. **Token (HTTP 401 / "Bad credentials").** The PAT is invalid, expired, or was
   never re-pasted after a rotation. Verify with `gh api user` (does it return
   the token owner's expected login?). Fix via the Annual PAT rotation
   above — mint, re-paste `GH_TOKEN` at <https://claude.ai/code/routines>, verify.
   Note: a FATAL that *names* the token can be a misdiagnosis of a proxy 403/502
   — always confirm with `gh api user` before assuming expiry.
2. **REST egress (HTTP 502 on `api.github.com`).** The sandbox egress proxy is
   dropping/upstream-erroring GitHub REST calls. This is Anthropic-side
   infrastructure, not a repo/token fix — check the proxy policy at
   `/__agentproxy/status` and confirm `api.github.com` is permitted for the
   routine environment.
3. **GraphQL ("GraphQL proxying is not enabled", HTTP 403).** A property of the
   Anthropic egress proxy, **not user-configurable** (as of 2026-07 — undocumented,
   no env toggle; both `api.github.com` and `gist.github.com` are domain-allowlisted
   yet GraphQL and gist *writes* are blocked at the operation level). **No cloud
   routine uses GraphQL anymore** — the Custodian's `bot-thread-resolve` task was
   dropped in the 2026-07 consolidation for exactly this reason; its replacement
   is the deterministic review-thread-janitor workflow in `dryvist/ai-workflows`
   (GHA runners have normal egress, GraphQL works there — same reason
   issue-solver and routine-monitor live in GHA). If a cloud routine hits this
   error, a GraphQL call crept back into a prompt; remove it.
4. **Gist writes ("not permitted through this proxy", HTTP 403).** Categorical and
   unfixable — this is *why* state moved to `$STATE_REPO`. If you see this, a
   routine is still attempting a gist write; it should be using the Contents API
   (`_common/state-file.md`) instead.
5. **State file (`state_fallback=true` banner, not FATAL).** Soft: the routine ran
   but couldn't read/write its `state/<routine>.json` (repo missing, or a transient
   error). Confirm `$STATE_REPO` exists and the token can write it. Memory is
   degraded for that run only; it is never a substitute for a FATAL.
6. **Cloud GitHub connection ("not enabled for this session", HTTP 403 on every
   repo call).** The cloud sandbox's GitHub access rides a proxy-scoped credential
   from the claude.ai ACCOUNT's GitHub connection, not `GH_TOKEN` alone. A GitHub
   account/org rename invalidates it — every repo API call 403s regardless of
   token validity (observed after the 2026-06 account rename). Fix: re-run
   `/web-setup` on claude.ai to re-bind the GitHub connection, then smoke-test
   below. No prompt or env change helps until that is done.

After a fix, re-run estate-briefing first (cheapest read-only smoke test) and
confirm it writes `state/estate-briefing.json` in `$STATE_REPO` before releasing
the rest. The daily `routine-monitor.yml` workflow will independently flag any
routine whose state stops updating.
