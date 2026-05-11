---
name: Bug report
about: A run produced wrong / malformed output, or a script crashed
labels: bug
---

## What happened

<!-- Brief description of the unexpected behavior -->

## How to reproduce

The command(s) you ran:

```
/decision-battle-royale ...
```

Or the script invocation:

```bash
bash ~/.claude/skills/decision-battle-royale/scripts/quick-battle.sh ...
```

## What you expected

## What actually happened

<!-- Paste relevant output. If the parser failed, include the verdict.md and
     the parse-verdict.sh error message. -->

## Audit trail (helps a lot)

If the battle reached the judge stage, the following files are extremely
useful — feel free to redact any sensitive content first:

- `<battle-dir>/output/round-*/match-*/prompt-judge.md` (the rendered judge prompt)
- `<battle-dir>/output/round-*/match-*/verdict.md` (the judge's raw output)
- `<battle-dir>/output/round-*/match-*/verdict.json` (the parser output, if any)

## Environment

- macOS / Linux: 
- bash version (`bash --version | head -1`): 
- python3 version (`python3 --version`): 
- Claude Code version: 
- Skill version (from `CHANGELOG.md`): 
