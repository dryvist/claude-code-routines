# Deploy routines

Instructions for Claude when invoked by `.github/workflows/deploy-routines.yml`.

For every file matching `routines/*.prompt.md` in this checkout:

1. Read the file. Parse the YAML frontmatter for `trigger_id`, `model`,
   and `allowed_tools`. If the frontmatter has no `trigger_id` field
   (the prompt has been migrated to a native GitHub Actions workflow
   and is no longer a cloud routine), print
   `SKIP <basename> (no trigger_id — managed by GHA)` and move on.
2. Extract the body below the closing `---` of the frontmatter — call
   it BODY.
3. Call `RemoteTrigger` with `action: get` for the `trigger_id`. Extract
   the current cloud body from
   `job_config.ccr.events[0].data.message.content`. If it equals BODY
   exactly, print `SKIP <basename> (in sync)` and move to the next file
   — do not call `update`.
4. If BODY differs, call the `RemoteTrigger` tool with `action: update`,
   the file's `trigger_id`, and this body shape:

   ```json
   {
     "job_config": {
       "ccr": {
         "events": [{
           "data": {
             "message": {
               "content": "<BODY>",
               "role": "user"
             },
             "type": "user"
           }
         }],
         "session_context": {
           "allowed_tools": "<from frontmatter>",
           "model": "<from frontmatter>"
         }
       }
     }
   }
   ```

5. Verify the update by calling `RemoteTrigger` `action: get` for the
   same `trigger_id` and confirming the returned
   `job_config.ccr.events[0].data.message.content` equals BODY exactly.

Print one `PASS <basename>`, `SKIP <basename> (in sync)`, or
`FAIL <basename> — <reason>` line per file. Exit non-zero if any FAIL.

Do not modify this repository.
