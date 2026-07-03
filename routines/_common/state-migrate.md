**One-run state migration (remove this block after 2026-07-20).** This routine
was renamed or merged; its cross-run memory may still live at one or more old
paths. `$OLD_STATE_PATHS` (space-separated, set by this routine just above this
block) lists them in priority order.

If the read of `$STATE_PATH` returns **404**, before treating this as a first
run, try each path in `$OLD_STATE_PATHS` in order against the same `data`
branch. For each old file found:

1. Parse it and merge its fields into this routine's current schema. Fields the
   current schema does not define are dropped; this routine's state section may
   specify extra per-field mapping rules — those win.
2. PUT the merged content to `$STATE_PATH` (create — no `sha`), using the
   standard `put_state` recipe.
3. DELETE the old file:

   ```bash
   OLD_SHA=$(gh api "repos/$STATE_REPO/contents/$OLD_PATH?ref=data" --jq .sha)
   jq -n --arg msg "chore(state): migrate $OLD_PATH -> $STATE_PATH" \
     --arg sha "$OLD_SHA" --arg branch data \
     --arg cname "$GIT_COMMITTER_NAME" --arg cemail "$GIT_COMMITTER_EMAIL" \
     '{message:$msg, sha:$sha, branch:$branch,
       committer:{name:$cname, email:$cemail}}' \
   | gh api "repos/$STATE_REPO/contents/$OLD_PATH" -X DELETE --input -
   ```

If the DELETE fails, proceed anyway and add one line to the Slack message naming
the leftover file. If neither the new nor any old path exists, this is a genuine
first run — create-if-missing per the state-file rules. Never run the migration
when `$STATE_PATH` already exists.
