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

> **This deployment (dryvist), as of 2026-07-01:** the runtime identity is a
> `JacobPEvans-personal` **user** PAT (not a GitHub App bot) with write access
> to the `dryvist` (`$GH_OWNER`) operational repos **and** to the private state
> repo `$STATE_REPO` (`JacobPEvans-personal/routine-state`). Commits therefore
> attribute to that user via the Contents API `committer` object. State is JSON
> files in `$STATE_REPO` (`state/<routine>.json` + `pr-budget.json`) — **cloud
> routines cannot use gists**, the egress proxy blocks gist writes
> (`"Gist writes are not permitted through this proxy"`, HTTP 403). The
> account-agnostic App-bot runbook below still works for a fresh fork; the
> App-vs-user-PAT choice only changes `author.login` on landed commits.

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
- Issues: Read and write (Custodian needs this for label edits and
  the repo-audit issue it creates)
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

At <https://claude.ai/code/routines>, on the env shared by all five
routines:

- `GH_TOKEN` — the runtime PAT from step 2. Must also have write access to
  the state repo below (mint it for the operational repos **plus**
  `$STATE_REPO`).
- `GH_OWNER` — the org or user that owns the target repos
  (e.g. `acme-corp`).
- `STATE_REPO` — `owner/repo` of the private cross-run state store
  (e.g. `JacobPEvans-personal/routine-state`). Create it as an empty private
  repo owned by the token's user before first run; routines create
  `state/<routine>.json` and `pr-budget.json` on demand via the Contents API.
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

Trigger any routine (Daily Polish is cheapest) and inspect the resulting
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
   the expected `JacobPEvans-personal` login?). Fix via the Annual PAT rotation
   above — mint, re-paste `GH_TOKEN` at <https://claude.ai/code/routines>, verify.
   Note: a FATAL that *names* the token can be a misdiagnosis of a proxy 403/502
   — always confirm with `gh api user` before assuming expiry.
2. **REST egress (HTTP 502 on `api.github.com`).** The sandbox egress proxy is
   dropping/upstream-erroring GitHub REST calls. This is Anthropic-side
   infrastructure, not a repo/token fix — check the proxy policy at
   `/__agentproxy/status` and confirm `api.github.com` is permitted for the
   routine environment.
3. **GraphQL ("GraphQL proxying is not enabled", HTTP 403).** Distinct from the
   hard gist block — this reads as an *enable-able* proxy setting. Custodian uses
   `gh api graphql`; enable GraphQL proxying in the routine env, or those specific
   calls stay unavailable (the rest of the routine still runs).
4. **Gist writes ("not permitted through this proxy", HTTP 403).** Categorical and
   unfixable — this is *why* state moved to `$STATE_REPO`. If you see this, a
   routine is still attempting a gist write; it should be using the Contents API
   (`_common/state-file.md`) instead.
5. **State file (`state_fallback=true` banner, not FATAL).** Soft: the routine ran
   but couldn't read/write its `state/<routine>.json` (repo missing, or a transient
   error). Confirm `$STATE_REPO` exists and the token can write it. Memory is
   degraded for that run only; it is never a substitute for a FATAL.

After a fix, re-run The Observer first (cheapest read-only smoke test) and confirm
it writes `state/observer.json` in `$STATE_REPO` before releasing the rest.
