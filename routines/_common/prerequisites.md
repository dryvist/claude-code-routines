`gh`, `jq`, `base64`, `sha256sum` are pre-installed. `gh` is authenticated via `GH_TOKEN`. Required env vars:

- `GH_TOKEN` — PAT with `repo` + `read:org` scopes.
- `GH_OWNER` — single owner/org.
- `GIT_COMMITTER_NAME` / `GIT_COMMITTER_EMAIL` — bot identity for the Contents API committer object.
- `PROMPT_SOURCE_URL` — link to this prompt for Provenance.
- `ROUTINE_PAUSED` — kill switch.
