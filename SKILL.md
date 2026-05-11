---
name: decision-battle-royale
description: Help the user decide between 2 or 4 ideas, options, plans, or strategies by running a structured AI tournament. Each option is defended by an independent fresh-context Claude subagent in parallel; a separate fresh-context Claude subagent acts as a skeptical judge with WebSearch verification. The orchestrator (you) never reads defenses or verdicts — only spawns subagents and runs bash scripts — so your conversation's framing cannot bias the result. Triggers on phrases like "decide between these", "which option is best", "compare these ideas", "second opinion on which to pick", "have agents debate", "battle these options", "score these against a rubric", "/decision-battle-royale", "/decision-battle", or the legacy "/battle-royale". Use when the user has 2-4 candidate ideas/specs (as files or paths) and wants a defensible, auditable verdict. Prefer the one-shot inline mode (`run-inline`) when the user just passes file paths.
---

# Decision Battle Royale — Decide between options with fresh-context AI judges

A skill for deciding between 2 or 4 candidate ideas, options, plans, or strategies — through a structured tournament where each option gets a zealous AI advocate and a separate fresh-context AI judge picks the winner.

**Core principle:** the orchestration flow is deterministic. The orchestrator (Claude in this session) only does two things: (1) spawn subagents with prompts, (2) run bash scripts. Defending ideas and judging are done by **fresh-context Claude subagents**. Grade parsing, bracket advancement, and reporting are done by **bash scripts**. **Do not interpret defenses or judgments yourself.** This is what eliminates orchestrator bias structurally.

---

## When to use

Use when the user has 2 or 4 candidate ideas/options/plans/strategies and wants a structured comparison that:
- **Avoids self-evaluation bias** — the session that helped generate the options is not the one judging
- **Forces evidence-based grading** — the judge defaults every interpretive claim to "unverified" and uses WebSearch to upgrade or downgrade
- **Surfaces strong-form arguments** via adversarial defense — each option gets a zealous advocate
- **Produces auditable results** — every prompt and response saved to disk, every WebSearch query logged

Natural-language triggers: *"decide between these"*, *"which option is best"*, *"compare these ideas"*, *"second opinion on which to pick"*, *"battle these options"*, *"have agents debate"*, *"score these against a rubric"*, *"rank these specs"*, *"battle royale"*, *"/decision-battle-royale"*, *"/decision-battle"*, *"/battle-royale"* (legacy).

Not a fit for: single-option go/no-go decisions, decisions with >4 candidates (cull first), or decisions where the user doesn't have written specs yet (have them write the specs first — the act of writing often reveals the answer).

---

## Two ways to run a battle

### 1. **One-shot inline mode (preferred)** — `run-inline`

When the user has the idea documents already written and just gives you their paths, use this. It scaffolds and runs in one shot.

**Invocation patterns from the user:**
- *"`/decision-battle-royale` decide between `~/specs/option-a.md` and `~/specs/option-b.md`"*
- *"Battle these two ideas: `path/to/idea1.md` and `path/to/idea2.md`. Context is `path/to/market.md`."*
- *"Run a 4-way decision battle on `a.md b.md c.md d.md`."*

**Procedure:**

1. **Identify the idea paths** from the user's message. Expect exactly 2 or 4 paths to readable `.md` files. If the user gave inline text instead of paths, ask them to save the specs first — the system needs files for the audit trail.
2. **Identify optional flags:**
   - context file (look for "context is X", "shared context X", or `--context X`)
   - battle name (look for "name it X", or `--name`)
   - rubric (default `balanced`; look for `--rubric`)
3. **Run `quick-battle.sh`** with the resolved args. Capture the battle dir from its last stdout line:
   ```bash
   BATTLE_DIR=$(bash ~/.claude/skills/decision-battle-royale/scripts/quick-battle.sh \
     <idea1.md> <idea2.md> [<idea3.md> <idea4.md>] \
     [--context <ctx.md>] [--name "..."] | tail -1)
   ```
4. **Tell the user** the battle directory and the contestants you extracted, then **proceed directly to the standard battle pipeline** (Steps 2-6 in the "Full run procedure" section below) using that battle dir.

If the user only describes the ideas in prose without paths, ask them to save each idea as a markdown file first. The audit trail is the whole point — running on ephemeral prose defeats it.

### 2. **Full setup mode** — `init` then `run`

When the user is starting from scratch and wants the system to scaffold stub files for them to fill in:

```bash
bash ~/.claude/skills/decision-battle-royale/scripts/init-battle.sh <dir> --name "Name"
```

Then the user fills in `<dir>/battle.yaml`, `<dir>/ideas/idea-*.md`, and `<dir>/context/shared-context.md` before invoking `run`.

---

## Commands

### `run-inline <idea1.md> <idea2.md> [<idea3.md> <idea4.md>]`

One-shot mode. Scaffolds via `quick-battle.sh` and runs the full pipeline. Optional flags: `--context <ctx.md>`, `--name "Title"`, `--rubric <name>`.

### `init <dir> [--name "Name"] [--rubric balanced]`

Scaffold a battle directory with stub files for the user to fill in. Run via Bash:
```bash
bash ~/.claude/skills/decision-battle-royale/scripts/init-battle.sh <dir> --name "Name"
```

### `run <dir>`

Run the full pipeline on an existing battle directory. Follow the procedure below.

### `rerun <dir> --rubric <new>`

Re-judge existing defender outputs under a different rubric. Defenders are NOT re-spawned; only judges are re-invoked. Cheap rubric-sensitivity test.

### `status <dir>`

```bash
cat <dir>/output/state.json | python3 -m json.tool
```

### `summary <dir>`

```bash
bash ~/.claude/skills/decision-battle-royale/scripts/summary.sh <dir>
```

---

## Full run procedure

This is the precise sequence after the battle dir exists (either via `init` + fill or via `run-inline` scaffolding). Do NOT improvise. Each step is either a bash script invocation or a parallel Agent spawn.

### Step 1 — Validate the battle

```bash
test -f <dir>/battle.yaml || echo "ERROR: missing battle.yaml"
test -d <dir>/ideas       || echo "ERROR: missing ideas/"
```

If validation fails, stop and report.

### Step 2 — Determine current round

```bash
bash ~/.claude/skills/decision-battle-royale/scripts/advance.sh <dir>
```

Writes `<dir>/output/state.json` and `<dir>/output/round-N/bracket.json`. If complete, skip to Step 6.

Read the bracket file to know which matches to run. Each match has: `id`, `contestants: [a_id, b_id]`.

### Step 3 — Defender phase (PARALLEL)

For each match in the current round:

1. For each contestant in the match (defender of A, defender of B):
   - Read the contestant's spec from `<dir>/ideas/<spec-path>` (per battle.yaml).
   - Read the opponent's spec.
   - Read the rubric (per battle.yaml `rubric:` field).
   - Read shared context (per battle.yaml `context:` field, if set).
   - Render the defender prompt via `render-prompt.sh` with env vars:
     ```bash
     CONTEST_NAME="..." \
     ROUND_NAME="..." \
     ROUND_TYPE="..." \
     IDEA_NAME="..." IDEA_SPEC="$(cat ...)" \
     OPPONENT_NAME="..." OPPONENT_SPEC="$(cat ...)" \
     RUBRIC_SUMMARY="$(cat ...)" \
     SHARED_CONTEXT="$(cat <dir>/context/...)" \
     bash ~/.claude/skills/decision-battle-royale/scripts/render-prompt.sh \
       ~/.claude/skills/decision-battle-royale/prompts/defender.tmpl.md \
       > <dir>/output/round-N/match-X/prompt-defender-<id>.md
     ```
2. **Spawn ALL defender subagents IN PARALLEL** using a single message with multiple Agent tool uses. Each defender:
   - Subagent type: `general-purpose`
   - Prompt: contents of the rendered prompt file
   - Description: `"Defender of <Idea Name>"`
3. When all defenders return, **save each output verbatim** to `<dir>/output/round-N/match-X/defender-<id>.md`.
4. **Do NOT read or interpret the defenders' content.** Just save the markdown.

### Step 4 — Judge phase (one judge per match, can run in parallel across matches)

For each match:

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
   bash ~/.claude/skills/decision-battle-royale/scripts/render-prompt.sh \
     ~/.claude/skills/decision-battle-royale/prompts/judge.tmpl.md \
     > <dir>/output/round-N/match-X/prompt-judge.md
   ```
2. **Spawn the judge subagent** (general-purpose, fresh context). The judge has WebSearch (budget 3 queries per match — enforced by prompt). Save output verbatim to `verdict.md`.
3. **Parse the verdict** with the bash script (do NOT interpret yourself):
   ```bash
   bash ~/.claude/skills/decision-battle-royale/scripts/parse-verdict.sh \
     <dir>/output/round-N/match-X/verdict.md \
     <rubric-path> \
     > <dir>/output/round-N/match-X/verdict.json
   ```
4. If parse fails (exit 2 or 3), spawn the judge subagent ONE more time with the same prompt prefixed by:
   `"Your previous output failed format validation. The grade table must match the rubric criteria exactly. Output ONLY the five required sections."`
   Then re-parse. If it fails twice, **stop and report to the user**; do not proceed.

### Step 5 — Advance the bracket

```bash
bash ~/.claude/skills/decision-battle-royale/scripts/advance.sh <dir>
```

If the battle is now complete, proceed to Step 6. Otherwise, loop back to Step 3 with the new round.

### Step 6 — Generate final report

```bash
bash ~/.claude/skills/decision-battle-royale/scripts/summary.sh <dir>
```

Read `<dir>/output/final-report.md` and present the headline result (winner + key reasoning) to the user. Link them to the file for the full audit trail.

---

## Critical rules for the orchestrator

1. **Do not interpret defender output or judge output.** Save verbatim, parse via bash. The whole point of the system is that the orchestrator cannot bias the contest.
2. **Do not modify the rubric mid-contest.** If the user wants a different rubric, run `rerun` with the new rubric file.
3. **Spawn defenders in parallel** (single message with multiple Agent tool uses). Sequential defender spawns are wrong — they leak information about timing.
4. **Each subagent gets independent context.** Use the Agent tool with no prior conversation context references. The prompt is self-contained.
5. **Save every prompt and every response.** Audit trail matters. Files are the source of truth.
6. **Don't skip the parse step.** If `parse-verdict.sh` fails, retry once with format reminder, then halt.
7. **For inline mode**, accept only file paths (not inline prose specs). The audit trail and the defender prompts both require files. If the user pastes prose, ask them to save it first.

---

## File layout

| File | Purpose |
|---|---|
| `~/.claude/skills/decision-battle-royale/SKILL.md` | This file |
| `~/.claude/skills/decision-battle-royale/prompts/defender.tmpl.md` | Defender prompt template with `{PLACEHOLDERS}` |
| `~/.claude/skills/decision-battle-royale/prompts/judge.tmpl.md` | Judge prompt template (v0.4 — The Skeptic with WebSearch) |
| `~/.claude/skills/decision-battle-royale/rubrics/balanced.yaml` | Default 5-criterion rubric mapped to investor decision logic |
| `~/.claude/skills/decision-battle-royale/scripts/quick-battle.sh` | One-shot scaffold from inline idea file paths |
| `~/.claude/skills/decision-battle-royale/scripts/init-battle.sh` | Scaffold a new battle directory with stub files |
| `~/.claude/skills/decision-battle-royale/scripts/render-prompt.sh` | Substitute `{VAR}` from env into a template |
| `~/.claude/skills/decision-battle-royale/scripts/parse-verdict.sh` | Extract grades + reasoning from a judge verdict |
| `~/.claude/skills/decision-battle-royale/scripts/advance.sh` | Determine winners, write next-round config |
| `~/.claude/skills/decision-battle-royale/scripts/summary.sh` | Render final markdown report |
| `~/.claude/skills/decision-battle-royale/examples/<name>/` | Worked examples |
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
| `balanced.yaml` | 5 criteria mapped to a 5-step investor decision logic (Category & Ceiling → Wedge & Traction → Architecture & Moat → Trust → Execution) | Product/strategy idea selection |

Each criterion is graded **Strong (+1)** / **Neutral (0)** / **Weak (−1)** with 2+ quoted proofs required and a verification status (✓ verified / ⚠ partial / ✗ unverified). Differential = Σ (grade × weight). The numeric 1-10 scoring used in v0.1 was replaced in v0.2 because LLMs collapse to a 6-8 gradient — the 3-grade system forces evidence-backed commitment.

To add a new rubric, drop a YAML file in `rubrics/` matching the schema of `balanced.yaml`.

---

## Version note (v0.4 — "The Skeptic" judge)

As of v0.4 the judge persona is **The Skeptic** — a blunt, evidence-obsessed critic who:

- Treats shared context as **authored and possibly biased**, not ground truth
- Defaults interpretive claims ("cannibalizes," "structurally cannot ship," "moat," "depends on") to **⚠ partial**
- Earns **✓ verified** only via primary source, multiple independent confirmations, or WebSearch (≤3 queries per match)
- Applies a **mandatory downgrade** when a critical interpretive claim is unverifiable: Strong with critical ⚠ → Neutral; Weak with critical ⚠ → Neutral

The judge output now requires a `## SEARCHES PERFORMED` section listing every WebSearch query + finding, or explicitly stating which interpretive claims were accepted on shared-context-only trust.

The legacy skill name `/battle-royale` continues to work as an alias for backward compatibility. See `CHANGELOG.md` for the full evolution from v0.1 (numeric scoring) through v0.5 (inline mode + rename).
