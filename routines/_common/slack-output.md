Slack output is mandatory: emit exactly one of this routine's templates per run, even on a no-op. Never exit silently. If `gist_fallback=true` was set, prepend a one-line warning to the message.

Sanitize before posting. Slack's `<!channel>`, `<!here>`, `<@USERID>`, `<#CHANNEL>`, `<URL|text>` tokens can be smuggled through PR titles, issue bodies, and alert names. Every field derived from repo content MUST pass the redaction set (Hard Rules) and then have `<` / `>` escaped — literal control tokens this routine's own templates emit deliberately are exempt:

```bash
safe() { jq -Rr 'gsub("<"; "‹") | gsub(">"; "›")'; }
echo "${untrusted_title}" | safe
```
