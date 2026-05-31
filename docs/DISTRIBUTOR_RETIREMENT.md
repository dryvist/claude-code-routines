# Distributor retirement — 2026-05-30

The Distributor cloud routine
(`trigger_id: trig_01HoVTrJjo41JFEyzmY1tU5b`) is retired. Its job —
propagating thin workflow callers from
[`dryvist/ai-workflows`](https://github.com/dryvist/ai-workflows) into
every repo in the estate via per-repo Contents API PUTs — is now handled
by GitHub org **Required Workflows** on the `dryvist` org. Per-repo
caller files are no longer needed for dryvist repos.

This doc captures the migration so the user can configure Required
Workflows manually with the same coverage The Distributor would have
provided.

## Why retire

- **DRY violation.** The Distributor's whole job is to keep N per-repo
  caller files in sync with the central reusable workflows. Org Required
  Workflows let the org admin declare "every repo matching these
  selectors must run these workflows on every PR" — zero per-repo files.
- **No state to lose.** The cloud routine never ran successfully — there
  is no `distributor-state` gist, so no `closed_pairs` opt-out history or
  per-tier opt-out memory to preserve.
- **Personal-account coverage trade-off.** Org Required Workflows only
  apply to org-owned repos. `JacobPEvans-personal/*` repos will not
  receive workflow coverage from Required Workflows. Either migrate those
  repos to `dryvist`, or accept tier-workflow drift on the personal
  account.

## What needs to happen (user-only operator steps)

These steps require an org-admin token tier (`gh-claude-org-admin`) and
manual UI access. Do them in order:

### 1. Delete the cloud routine

Visit `https://claude.ai/code/routines`, find the entry for The
Distributor (`trigger_id: trig_01HoVTrJjo41JFEyzmY1tU5b`), and delete
it. Confirm via `RemoteTrigger get trigger_01HoVTrJjo41JFEyzmY1tU5b`
returns 404.

### 2. Configure org Required Workflows on `dryvist`

The Distributor's tier table maps to four Required Workflow sets. For
each tier, create a Required Workflow in the dryvist org settings
pointing at the corresponding `dryvist/ai-workflows` reusable workflow,
SHA-pinned to a tagged release (e.g. `v0.3.0`).

GitHub's Required Workflow selector is a static list of repos, not a
file-system predicate. Use `gh repo list dryvist --json name,topics` to
build the per-tier repo list and feed it into the Required Workflow
configuration.

#### Tier: `core`

- **Selector:** All non-archived repos.
- **Workflows:**
  - `link-checker.lock.yml`
  - `daily-malicious-code-scan.lock.yml`
  - `ci-doctor.lock.yml`
  - `sub-issue-closer.lock.yml`
  - `gh-aw-pin-refresh.yml`
  - `release-please.yml`
- **Secrets:** uses runner-injected `GITHUB_TOKEN` only.

#### Tier: `tests`

- **Selector:** Repos with `tests/` dir OR any `*_test.*` / `*.test.*` /
  `*.spec.*` file.
- **Workflows:**
  - `ci-fix.yml`
  - `ci-fail-issue.yml`
  - `post-merge-tests.yml`
- **Secrets:** `ANTHROPIC_API_KEY` per repo. Distribute via
  `dryvist/secrets-sync`.

#### Tier: `nix`

- **Selector:** Repos with `flake.nix` at root.
- **Workflows:**
  - `osv-scan.yml`
- **Secrets:** none.

#### Tier: `terraform`

- **Selector:** Repos with any `*.tf` at root OR `terragrunt.hcl`.
- **Workflows:**
  - `terraform.yml`
- **Secrets:** none.

### 3. Honor existing `skip-distributor` opt-outs

The Distributor supported per-tier opt-out via GitHub topic
(`skip-distributor` or `skip-distributor-<tier>`). Required Workflows
don't read topics, so opt-outs become explicit repo-list exclusions.

Audit existing opt-outs with:

```bash
gh repo list dryvist --topic skip-distributor --limit 100 \
  --json name,repositoryTopics
```

For each repo + topic combination, remove that repo from the
corresponding tier's Required Workflow selector. Leave the topic in
place as a documentation marker (no enforcement effect).

### 4. Hard-excludes

These repos must never be added to any tier's Required Workflow
selector (preserve the Distributor's original hard-exclude list):

- Archived repos.
- `dryvist/ai-workflows` (the source, not a consumer).
- Upstream mirrors: `dryvist/agentics`, `dryvist/agent-os`.
- Profile/meta repos: `dryvist/dryvist`, `dryvist/dryvist.github.io`,
  `dryvist/.github`.
- Abandoned: `dryvist/tf-static-website`.
- Splunk-app legacy repos that intentionally have zero workflows.

### 5. Personal-account repos (`JacobPEvans-personal/*`)

Required Workflows don't apply at the user-account level. Three options:

1. **Migrate** the personal repo to `dryvist` and let Required Workflows
   take effect. Recommended for active repos.
2. **Manually maintain** caller files in the personal repo. Highest
   maintenance burden.
3. **Accept drift**. Acceptable for archived or low-activity personal
   repos.

The user picks per repo. No automation handles this.

## Verification

After steps 1–4 complete:

- `RemoteTrigger get trigger_01HoVTrJjo41JFEyzmY1tU5b` returns 404.
- No new PRs with the `[routine:distributor]` title suffix appear in any
  repo.
- A test PR opened in one repo per tier (e.g. one `tests`-tier repo, one
  `nix`-tier repo) fires the right reusable workflows without any caller
  file present in the repo.
- One week post-retirement: spot-check 5 random consumer repos to
  confirm they still get the workflow runs they used to get from
  Distributor-injected callers (link-checker, ci-doctor, etc.).

## Status

- **Retired in repo:** 2026-05-30 (this PR).
- **Cloud routine deleted:** pending user-only step 1.
- **Required Workflows configured:** pending user-only step 2.
- **Personal-account decision:** pending per-repo user judgment.
