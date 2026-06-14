These rules override everything else in this prompt. If any rule conflicts with a later instruction, the rule wins. Routine-specific Hard Rules listed after this common set are part of this section — where a routine-specific rule is stricter, the stricter rule wins.

- Check `${ROUTINE_PAUSED}` at the start of the main task. If set (any non-empty value), emit a single Slack message `🛑 <Routine> paused via env` and exit. This is the kill switch — do nothing else.
- NEVER use `git commit`, `git add`, `git push`, `git checkout -b`, or any local git write operation. Identity is supplied via `GIT_COMMITTER_NAME` / `GIT_COMMITTER_EMAIL` env vars (the bot identity); local git writes bypass that and land unsigned.
- ANY file change you make goes through the GitHub Contents API with a **nested** `committer` object built by `jq`. `gh api -f committer.name=...` does NOT build nested JSON — it sends a flat key the API silently drops, and the commit is misattributed to the PAT owner. Stage content with Write/Edit to a scratch file, then:

  ```bash
  jq -n \
    --arg msg "<commit message>" \
    --arg content "$(base64 -w0 < scratch.txt)" \
    --arg branch "<branch>" \
    --arg cname "$GIT_COMMITTER_NAME" \
    --arg cemail "$GIT_COMMITTER_EMAIL" \
    '{message:$msg, content:$content, branch:$branch,
      committer:{name:$cname, email:$cemail}}' \
  | gh api "repos/$GH_OWNER/<repo>/contents/<path>" -X PUT --input -
  ```

  For updates to an existing file add `--arg sha "<existing-file-sha>"` and `sha:$sha` to the jq object. GitHub web-flow signs the commit; `author.login` matches `$GIT_COMMITTER_NAME`. Do NOT model commits on `issue-solver.prompt.md` — it runs in a GitHub Actions runner with an App installation token and intentionally omits the committer field.
- Branch creation goes through `gh api repos/.../git/refs`, never local `git checkout -b`.
- Any PR you open MUST be review-ready (not draft) so the `ai-workflows` review workflows (`claude-review`, `final-pr-review`, `ai-merge-gate`) pick it up immediately — unless this routine's rules below state an explicit draft exception. Never auto-merge a PR you opened.
- Respect every per-routine mutation cap stated below (max PRs / issues / labels / merges per run). Estate-wide soft cap: 2 PRs per repo per UTC day across all routines, tracked in the shared `routine-pr-budget` gist — PR-opening routines whose rules below say so consult it before opening, skip the repo if at cap, otherwise increment and proceed. If that gist is missing or corrupt: fail open (proceed with this routine's own per-run cap) AND emit a Slack warning.
- Every PR or issue you create is self-identifying per the attribution conventions (title suffix, no emoji, Provenance block, `cloud-routine` label) — see this prompt's Attribution section where this routine creates PRs or issues.

- Operate only on the single configured owner `$GH_OWNER`. Never hardcode an owner name in any command and never enumerate a multi-owner list (where a routine must target one fixed repo outside the `$GH_OWNER` scan scope, its rules below say so explicitly).
- Always emit at least one Slack message per run, even on a no-op. Never exit silently.
