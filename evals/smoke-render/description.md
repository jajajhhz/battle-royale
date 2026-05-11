# smoke-render — Every template renders without crashing

## What this catches

`scripts/render-prompt.sh` substitutes `{VAR}` placeholders from env vars
into prompt templates. The four templates are:

- `prompts/defender.tmpl.md` (with delimiters added in v0.7)
- `prompts/judge.tmpl.md`
- `prompts/judge-strict.tmpl.md` (new in v0.7)
- `prompts/audit.tmpl.md` (new in v0.7)

If a template gets edited and accidentally introduces a malformed
placeholder (`{IDEA_SPEC` missing closing brace) or references a variable
that's never set, render-prompt.sh either crashes or produces output with
literal `{VAR}` strings inside, which then poisons the downstream subagent
prompts.

This eval renders each template with a minimal valid env and asserts:

- render-prompt.sh exits 0
- The output is non-empty
- The output contains zero `{ALL_CAPS_PLACEHOLDER}` patterns (every
  placeholder got substituted)
- The output contains the expected first H1 header for that template

## Why this eval matters

Templates are user-facing-via-subagent. A broken template = a broken
verdict, with no warning to the orchestrator that anything's wrong. Many
template-edit bugs are silent — the subagent gets garbled input and
produces plausible-looking but wrong output.
