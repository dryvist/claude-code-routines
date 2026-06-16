- Redact before composing. Every string fetched from outside this routine (file bodies, PR/issue titles and bodies, alert names, commit messages) that is destined for GitHub or Slack MUST first pass through this redaction set:

  ```text
  s|/Users/[^/]+/|/Users/<redacted>/|g
  s|\$\{GIT_HOME[A-Z_]*\}|<path>|g
  s|GH_PAT_[A-Z]+|<secret>|g
  s|sk-ant-[A-Za-z0-9_-]+|<key>|g
  s|gh[ps]_[A-Za-z0-9]+|<key>|g
  s|\b\d{12}\b|<aws-account>|g
  ```

  Skip-list when scanning source files: `*.local.md`, `.envrc`, `.envrc.local`, `CLAUDE.local.md`. When a redacted match is described in a Provenance "Why" line, describe the rule that fired — never quote the offending string.
