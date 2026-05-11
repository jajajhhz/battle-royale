# frontmatter-conventions — SKILL.md frontmatter is Anthropic-spec compliant

## What this catches

The [Anthropic skill spec](https://agentskills.io/specification) defines
exactly six frontmatter fields. Two are required (`name`, `description`)
with hard limits (name ≤64 chars, lowercase-and-hyphens, must match
directory; description ≤1024 chars). The optional fields are `license`,
`compatibility`, `metadata`, `allowed-tools`. Anything else is
out-of-spec and may cause skill registries / loaders to reject the skill.

This eval parses SKILL.md and asserts:

- `name` exists, is ≤64 chars, lowercase with hyphens only
- `name` matches the parent directory name (when copied to
  `~/.claude/skills/<name>/SKILL.md`)
- `description` exists, ≤1024 chars
- `license` is present (every official Anthropic skill has one)
- No unknown frontmatter fields are present
- The description contains at least one of our documented trigger phrases
  (`decide between`, `which option is best`, `compare these ideas`,
  `decision-battle-royale`) — otherwise the skill won't auto-activate

## Why this eval matters

The description field is the single most important text in the entire
skill — it's what determines whether the skill auto-activates on a user's
natural-language query. If we accidentally rewrite the description in a
way that drops our trigger phrases, the skill silently stops responding
to natural-language invocations and only works on the literal slash
command.

A 1024-char limit means it's easy to bump past the cap as we add new
features. This eval catches that before it causes a registry rejection.
