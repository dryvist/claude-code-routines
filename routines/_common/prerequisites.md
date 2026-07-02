`gh`, `jq`, `base64`, `sha256sum` are pre-installed. `gh` is authenticated via `GH_TOKEN`. Required env vars:

- `GH_TOKEN` — a `JacobPEvans-personal` **user** PAT with write access to the `$GH_OWNER` repos this routine touches **and** to `$STATE_REPO`. Fine-grained is preferred (scoped to those repos + the state repo). No `gist` scope is needed — cloud routines cannot write gists (the egress proxy blocks them); all state lives in `$STATE_REPO` via the Contents API.
- `GH_OWNER` — single owner/org the routine operates on (`dryvist`).
- `STATE_REPO` — `owner/repo` of the private cross-run state repo (e.g. `JacobPEvans-personal/routine-state`), owned by the token's user so writes need no org grant.
- `GIT_COMMITTER_NAME` / `GIT_COMMITTER_EMAIL` — bot identity for the Contents API committer object.
- `PROMPT_SOURCE_URL` — link to this prompt for Provenance.
- `ROUTINE_PAUSED` — kill switch.
