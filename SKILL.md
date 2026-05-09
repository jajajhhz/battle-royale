---
name: battle-royale
description: Run an adversarial AI-judged contest of ideas, plans, or strategies. Use when the user wants to compare 2 or 4 candidate ideas through structured defender + judge subagents with a calibrated rubric. Each idea is defended by an independent Claude subagent in parallel; a separate Claude subagent judges with no shared context. The orchestration is bash-driven and deterministic — the orchestrator only spawns subagents and runs scripts; it does not interpret defenses or pick winners.
---

# Battle Royale — Idea Contest Orchestrator

A skill for running adversarial AI-judged contests of product ideas, plans, or strategies — with structurally enforced fairness.

**Core principle:** the orchestration flow is deterministic. The orchestrator (Claude in this session) only does two things in the contest itself: (1) spawn subagents with prompts, (2) run bash scripts. Defending ideas and judging are done by **fresh-context Claude subagents**. Score parsing, bracket advancement, and reporting are done by **bash scripts**. **Do not interpret defenses or judgments yourself.**

---

## When to use

Use when the user has 2 or 4 candidate ideas/plans/strategies and wants a structured comparison that:
- Eliminates orchestrator bias (the session that's helping the user is not the one judging)
- Forces evidence-based scoring (judges grounded in shared context, not rhetoric)
- Surfaces strong-form arguments via adversarial defense (each idea gets a zealous advocate)
- Produces auditable results (every prompt + response saved to disk)

Triggers: user says "battle royale", "score these ideas", "have agents debate", "rank these options against [rubric]", "/battle-royale".

## Commands

### `/battle-royale init <dir> [--name "Name"] [--rubric balanced]`

Scaffold a new battle directory. Run via Bash:
```bash
bash ~/.claude/skills/battle-royale/scripts/init-battle.sh <dir> --name "Name"
```
Creates `<dir>/battle.yaml`, stub `ideas/idea-{1..4}.md`, and `context/shared-context.md`. The user fills these in.

### `/battle-royale run <dir>`

Run the contest end-to-end. This is the main command. Follow the procedure below precisely.

### `/battle-royale rerun <dir> --rubric <new>`

Re-judge existing defender outputs under a different rubric. Defenders are NOT re-spawned; only judges are re-invoked. Cheap rubric-sensitivity test.

### `/battle-royale status <dir>`

Display the current state of a battle:
```bash
cat <dir>/output/state.json | python3 -m json.tool
```

### `/battle-royale summary <dir>`

Render the final report:
```bash
bash ~/.claude/skills/battle-royale/scripts/summary.sh <dir>
```

---

## How `/battle-royale run <dir>` works

This is a precise procedure. Do NOT improvise. Each step is either a bash script invocation or a parallel Agent spawn.

### Step 1 — Validate the battle

```bash
test -f <dir>/battle.yaml || echo "ERROR: missing battle.yaml"
test -d <dir>/ideas       || echo "ERROR: missing ideas/"
```

If validation fails, stop and report.

### Step 2 — Determine current round

```bash
bash ~/.claude/skills/battle-royale/scripts/advance.sh <dir>
```

This writes `<dir>/output/state.json` and `<dir>/output/round-N/bracket.json` for the current round. If the battle is already complete, skip to Step 6.

Read the bracket file to know which matches to run. Each match has: `id`, `contestants: [a_id, b_id]`.

### Step 3 — Defender phase (PARALLEL)

For each match in the current round:

1. For each contestant in the match (defender of A, defender of B):
   - Read the contestant's spec from `<dir>/ideas/<spec-path>` (per battle.yaml).
   - Read the opponent's spec.
   - Read the rubric (per battle.yaml `rubric:` field).
   - Read shared context (per battle.yaml `context:` field, if set).
   - Render the defender prompt by setting env vars and invoking `render-prompt.sh`:
     ```bash
     CONTEST_NAME="..." \
     ROUND_NAME="..." \
     ROUND_TYPE="..." \
     IDEA_NAME="..." IDEA_SPEC="$(cat ...)" \
     OPPONENT_NAME="..." OPPONENT_SPEC="$(cat ...)" \
     RUBRIC_SUMMARY="$(cat ...)" \
     SHARED_CONTEXT="$(cat <dir>/context/...)" \
     bash ~/.claude/skills/battle-royale/scripts/render-prompt.sh \
       ~/.claude/skills/battle-royale/prompts/defender.tmpl.md \
       > <dir>/output/round-N/match-X/prompt-defender-<id>.md
     ```
2. **Spawn ALL defender subagents IN PARALLEL** using a single message with multiple Agent tool uses. Each defender:
   - Subagent type: `general-purpose`
   - Prompt: contents of the rendered prompt file
   - Description: `"Defender of <Idea Name>"`
3. When all defenders return, **save each output verbatim** to `<dir>/output/round-N/match-X/defender-<id>.md`.
4. **Do NOT read or interpret the defenders' content.** Just save the markdown.

### Step 4 — Judge phase (one judge per match, can run in parallel across matches)

For each match in the current round:

1. Render the judge prompt:
   ```bash
   CONTEST_NAME="..." \
   ROUND_NAME="..." \
   IDEA_A_NAME="..." IDEA_B_NAME="..." \
   DEFENDER_A_OUTPUT="$(cat .../defender-<a>.md)" \
   DEFENDER_B_OUTPUT="$(cat .../defender-<b>.md)" \
   RUBRIC_FULL="$(cat <rubric>)" \
   SHARED_CONTEXT="$(cat .../context/...)" \
   MAX_SCORE="65" \
   bash ~/.claude/skills/battle-royale/scripts/render-prompt.sh \
     ~/.claude/skills/battle-royale/prompts/judge.tmpl.md \
     > <dir>/output/round-N/match-X/prompt-judge.md
   ```
2. **Spawn the judge subagent** (general-purpose, fresh context). Save output verbatim to `verdict.md`.
3. **Parse the verdict** with the bash script (do NOT interpret yourself):
   ```bash
   bash ~/.claude/skills/battle-royale/scripts/parse-verdict.sh \
     <dir>/output/round-N/match-X/verdict.md \
     <rubric-path> \
     > <dir>/output/round-N/match-X/verdict.json
   ```
4. If parse fails (exit 2 or 3), spawn the judge subagent ONE more time with the same prompt prefixed by:
   `"Your previous output failed format validation. The score table must match the rubric criteria exactly. Output ONLY the four required sections."`
   Then re-parse. If it fails twice, **stop and report to the user**; do not proceed.

### Step 5 — Advance the bracket

```bash
bash ~/.claude/skills/battle-royale/scripts/advance.sh <dir>
```

If the battle is now complete, proceed to Step 6. Otherwise, loop back to Step 3 with the new round.

### Step 6 — Generate final report

```bash
bash ~/.claude/skills/battle-royale/scripts/summary.sh <dir>
```

Output `<dir>/output/final-report.md`. Read it back and present the headline result to the user.

---

## Critical rules for the orchestrator

1. **Do not interpret defender output or judge output.** Save verbatim, parse via bash. The whole point of the system is that the orchestrator cannot bias the contest.
2. **Do not modify the rubric mid-contest.** If the user wants a different rubric, run `rerun` with the new rubric file.
3. **Spawn defenders in parallel** (single message with multiple Agent tool uses). Sequential defender spawns are wrong — they leak information about timing.
4. **Each subagent gets independent context.** Use the Agent tool with no prior conversation context references. The prompt is self-contained.
5. **Save every prompt and every response.** Audit trail matters. Files are the source of truth.
6. **Don't skip the parse step.** If `parse-verdict.sh` fails, retry once with format reminder, then halt.

---

## File layout

| File | Purpose |
|---|---|
| `~/.claude/skills/battle-royale/SKILL.md` | This file |
| `~/.claude/skills/battle-royale/prompts/defender.tmpl.md` | Defender prompt template with `{PLACEHOLDERS}` |
| `~/.claude/skills/battle-royale/prompts/judge.tmpl.md` | Judge prompt template |
| `~/.claude/skills/battle-royale/rubrics/balanced.yaml` | Default 5-criterion rubric mapped to investor decision logic |
| `~/.claude/skills/battle-royale/scripts/render-prompt.sh` | Substitute `{VAR}` from env into a template |
| `~/.claude/skills/battle-royale/scripts/parse-verdict.sh` | Extract scores + reasoning from a judge verdict |
| `~/.claude/skills/battle-royale/scripts/advance.sh` | Determine winners, write next-round config |
| `~/.claude/skills/battle-royale/scripts/summary.sh` | Render final markdown report |
| `~/.claude/skills/battle-royale/scripts/init-battle.sh` | Scaffold a new battle directory |
| `~/.claude/skills/battle-royale/examples/<name>/` | Worked examples |
| `<battle-dir>/battle.yaml` | Battle config (contestants, rubric, format) |
| `<battle-dir>/ideas/*.md` | Contestant specs |
| `<battle-dir>/context/*.md` | Shared judge context |
| `<battle-dir>/output/round-N/match-X/` | Per-match prompts, responses, parsed verdict |
| `<battle-dir>/output/state.json` | Current state of the battle |
| `<battle-dir>/output/final-report.md` | Final cumulative report |

---

## Existing rubrics

| Rubric | Criteria | Use case |
|---|---|---|
| `balanced.yaml` | 5 criteria mapped to a 5-step investor decision logic (Category & Ceiling → Wedge & Traction → Architecture & Moat → Trust → Execution) | Product idea selection |

To add a new rubric, drop a YAML file in `rubrics/` matching the schema of `balanced.yaml`.
