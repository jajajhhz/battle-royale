---
name: decision-battle-royale
description: Help the user decide between 2 or more ideas, options, plans, or strategies by running a structured single-elimination AI tournament. Each option is defended by an independent fresh-context Claude subagent in parallel; a separate fresh-context Claude subagent acts as a skeptical judge with WebSearch verification, and a third fresh-context audit subagent scores the judge's verdict quality and forces a strict re-judge on low scores. The orchestrator (you) never reads defenses or verdicts — only spawns subagents and runs bash scripts — so your conversation's framing cannot bias the result. Triggers on phrases like "decide between these", "which option is best", "compare these ideas", "second opinion on which to pick", "have agents debate", "battle these options", "score these against a rubric", "/decision-battle-royale", "/decision-battle", or the legacy "/battle-royale". Use when the user has 2 or more candidate ideas/specs (as files or paths) and wants a defensible, auditable verdict. Prefer the one-shot inline mode when the user just passes file paths. Bracket auto-builds with byes for non-powers-of-2 (N=3, 5, 6, 7, 9...); cost scales as N-1 matches × 3-4 subagents per match.
license: MIT
---

# Decision Battle Royale — Decide between options with fresh-context AI judges

A skill for deciding between **2 or more** candidate ideas, options, plans, or strategies — through a structured single-elimination tournament where each option gets a zealous AI advocate and a separate fresh-context AI judge picks the winner.

**Core principle:** the orchestration flow is deterministic. The orchestrator (Claude in this session) only does two things: (1) spawn subagents with prompts, (2) run bash scripts. Defending ideas and judging are done by **fresh-context Claude subagents**. Grade parsing, bracket advancement, and reporting are done by **bash scripts**. **Do not interpret defenses or judgments yourself.** This is what eliminates orchestrator bias structurally.

---

## When to use

Use when the user has 2 or more candidate ideas/options/plans/strategies and wants a structured comparison that:
- **Avoids self-evaluation bias** — the session that helped generate the options is not the one judging
- **Forces evidence-based grading** — the judge defaults every interpretive claim to "unverified" and uses WebSearch to upgrade or downgrade
- **Surfaces strong-form arguments** via adversarial defense — each option gets a zealous advocate
- **Produces auditable results** — every prompt and response saved to disk, every WebSearch query logged

Natural-language triggers: *"decide between these"*, *"which option is best"*, *"compare these ideas"*, *"second opinion on which to pick"*, *"battle these options"*, *"have agents debate"*, *"score these against a rubric"*, *"rank these specs"*, *"battle royale"*, *"/decision-battle-royale"*, *"/decision-battle"*, *"/battle-royale"* (legacy).

**Bracket sizes:** any N ≥ 2 is supported. For non-powers-of-2 (N = 3, 5, 6, 7, 9, ...) the first contestants in input order get byes in round 1 so every contestant plays at most one round less than the most-active contestant. Cost scales as **N − 1 matches × 3 Claude subagents per match** (2 defenders + 1 judge). `quick-battle.sh` warns at N > 16 and refuses N > 32 — at that scale cull your shortlist first or use a different tool.

Not a fit for: single-option go/no-go decisions, decisions where the user doesn't have written specs yet (have them write the specs first — the act of writing often reveals the answer), or decisions where the user wants a full ranking rather than a single winner (single-elimination only picks one champion).

---

## Two ways to run a battle

### 1. **One-shot inline mode (preferred)** — `run-inline`

When the user has the idea documents already written and just gives you their paths, use this. It scaffolds and runs in one shot.

**Invocation patterns from the user:**
- *"`/decision-battle-royale` decide between `~/specs/option-a.md` and `~/specs/option-b.md`"*
- *"Battle these two ideas: `path/to/idea1.md` and `path/to/idea2.md`. Context is `path/to/market.md`."*
- *"Run a 4-way decision battle on `a.md b.md c.md d.md`."*

**Procedure:**

1. **Identify the idea paths** from the user's message. Expect 2 or more paths to readable `.md` files. If the user gave inline text instead of paths, ask them to save the specs first — the system needs files for the audit trail. Any N ≥ 2 is supported; the bracket auto-builds with byes for non-powers-of-2.
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

### Step 3 — Defender phase (PARALLEL, write-to-disk protocol)

For each match in the current round:

1. For each contestant (defender of A, defender of B):
   - Read the contestant's spec, opponent's spec, rubric, shared context (paths in battle.yaml).
   - Render the defender prompt via `render-prompt.sh`. Note the new `OUTPUT_PATH` env var — this is the path the subagent will write its case to:
     ```bash
     CONTEST_NAME="..." \
     ROUND_NAME="..." \
     ROUND_TYPE="..." \
     IDEA_NAME="..." IDEA_SPEC="$(cat ...)" \
     OPPONENT_NAME="..." OPPONENT_SPEC="$(cat ...)" \
     RUBRIC_SUMMARY="$(cat ...)" \
     SHARED_CONTEXT="$(cat <dir>/context/...)" \
     OUTPUT_PATH="<dir>/output/round-N/match-X/defender-<id>.md" \
     bash ~/.claude/skills/decision-battle-royale/scripts/render-prompt.sh \
       ~/.claude/skills/decision-battle-royale/prompts/defender.tmpl.md \
       > <dir>/output/round-N/match-X/prompt-defender-<id>.md
     ```

2. **Spawn ALL defender subagents IN PARALLEL** (single message with multiple Agent tool uses):
   - Subagent type: `general-purpose`
   - Prompt: contents of the rendered prompt file
   - Description: `"Defender of <Idea Name>"`

3. **Write-to-disk protocol (v0.7+, adopted from agent-review-panel)**: Each defender writes its own case to the path given in `OUTPUT_PATH` and returns ONLY (a) the path it wrote to and (b) a 100-word neutral summary. **You — the orchestrator — must not display or quote the defender's full case in your response.** The judge will read from disk in the next step.

4. **Verify the file was written** for each defender:
   ```bash
   test -f <dir>/output/round-N/match-X/defender-<id>.md \
     || echo "ERROR: defender <id> did not write to disk"
   ```
   If a file is missing, re-spawn that defender ONE more time. If it fails twice, halt and report. The whole audit trail depends on these files existing.

5. **Why this matters**: keeping defender content out of the orchestrator's context window is what makes orchestrator bias structurally impossible, not just discouraged. If you read a defender's case into the response, the next subagent you spawn could see it via the conversation summary.

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

### Step 4b — Audit phase (verdict quality check, v0.7+)

The audit phase scores the *judge's verdict* on five quality axes
(verification rigor, downgrade consistency, evidence density, voice
calibration, search-budget use). This pattern is adapted from Anthropic's
Bloom evals' BloomMetaJudge — narrowed to per-verdict auditing.

For each match's verdict:

1. Render the audit prompt. The audit subagent sees ONLY the parsed
   `verdict.json` — not the defenses, not the specs, not the shared context.
   This information firewall is what makes the audit independent:
   ```bash
   CONTEST_NAME="..." \
   ROUND_NAME="..." \
   VERDICT_JSON="$(cat <dir>/output/round-N/match-X/verdict.json)" \
   bash ~/.claude/skills/decision-battle-royale/scripts/render-prompt.sh \
     ~/.claude/skills/decision-battle-royale/prompts/audit.tmpl.md \
     > <dir>/output/round-N/match-X/prompt-audit.md
   ```

2. **Spawn the audit subagent** (general-purpose, fresh context). No
   WebSearch needed — auditing is internal-rigor scoring, not fact-checking.
   Save its output verbatim to `<dir>/output/round-N/match-X/audit.md`.

3. **Parse and decide**:
   ```bash
   bash ~/.claude/skills/decision-battle-royale/scripts/audit-verdict.sh \
     <dir>/output/round-N/match-X/audit.md \
     <dir>/output/round-N/match-X/verdict.json
   exit_code=$?
   ```
   - Exit code 0 → audit PASSED. Verdict stands. Proceed to Step 5.
   - Exit code 1 → audit RETRY. Re-judge with the strict template (below).
   - Exit code 2 → audit malformed. Re-spawn the audit subagent once; if still malformed, log the failure and PASS the verdict (the original judge result is what's actionable; a broken audit shouldn't block).

4. **On audit RETRY**: re-render the judge prompt using
   `prompts/judge-strict.tmpl.md` with the audit's `justification` field
   passed in as `AUDIT_JUSTIFICATION`. Spawn a fresh judge subagent. Save
   the new verdict to a separate file (`verdict-strict.md` / `.json`)
   alongside the original — the audit trail keeps both. The strict
   verdict is what propagates to `state.json` and the final report.
   Only audit a strict verdict ONCE. If the strict re-judge also fails
   audit, accept it anyway with a flag in `state.json` (`audit_warning: true`).

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

## Why the orchestrator stays out

This section is conventions-with-reasons, not commandments. The reasons
matter because they explain when the convention can flex (rarely) versus
when it's load-bearing (usually).

- **Don't read or interpret subagent output.** The whole skill is built
  around the idea that the conversation that helped generate the options
  is not the one judging them. If the orchestrator reads a defender's
  case and summarizes it back to the user, that summary becomes
  conversational context — and the next subagent the orchestrator spawns
  can be influenced by it via the conversation summary. The write-to-disk
  protocol in Step 3 makes this structural, not just behavioral.

- **Don't change the rubric mid-contest.** Verdicts from different rubric
  versions aren't comparable. If the user wants to try a different rubric
  on the same defenses, use `rerun` — defenders stay the same, judge
  re-runs with new rubric.

- **Spawn defenders in parallel.** Sequential spawns leak timing
  information (e.g. defender B knows defender A is already done). One
  message, multiple Agent tool uses.

- **Each subagent is fresh-context.** Don't reference past conversation
  in the spawn prompt — the prompt is the entire context the subagent
  sees. This is what makes the verdicts independent.

- **Save every prompt and every response.** The file system is the
  source of truth, not your working memory. `rerun` and audits both
  depend on the files existing.

- **Retry parser failures once, then halt.** A second failure usually
  means the verdict format itself is wrong, which a third attempt won't
  fix. Halt with a clear error so the user can inspect.

- **Inline mode requires file paths, not pasted prose.** The defenders
  prompt and the audit trail both require persistent files. If the user
  pastes raw spec content into chat, ask them to save it as a `.md` file
  first.

---

## File layout

| File | Purpose |
|---|---|
| `~/.claude/skills/decision-battle-royale/SKILL.md` | This file |
| `~/.claude/skills/decision-battle-royale/prompts/defender.tmpl.md` | Defender prompt template (write-to-disk protocol) |
| `~/.claude/skills/decision-battle-royale/prompts/judge.tmpl.md` | Judge prompt template (The Skeptic with WebSearch) |
| `~/.claude/skills/decision-battle-royale/prompts/judge-strict.tmpl.md` | Strict re-judge template, used when audit RETRIES a verdict |
| `~/.claude/skills/decision-battle-royale/prompts/audit.tmpl.md` | Meta-judge prompt (adapted from Anthropic Bloom's MetaJudge) |
| `~/.claude/skills/decision-battle-royale/rubrics/balanced.yaml` | Default 5-criterion rubric mapped to investor decision logic |
| `~/.claude/skills/decision-battle-royale/scripts/quick-battle.sh` | One-shot scaffold from inline idea file paths |
| `~/.claude/skills/decision-battle-royale/scripts/init-battle.sh` | Scaffold a new battle directory with stub files |
| `~/.claude/skills/decision-battle-royale/scripts/render-prompt.sh` | Substitute `{VAR}` from env into a template |
| `~/.claude/skills/decision-battle-royale/scripts/parse-verdict.sh` | Extract grades + reasoning from a judge verdict |
| `~/.claude/skills/decision-battle-royale/scripts/audit-verdict.sh` | Parse meta-judge output, decide PASS/RETRY |
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

## Current judge persona

**The Skeptic** (since v0.4) + per-verdict audit + strict re-judge on
failure (since v0.7). See `CHANGELOG.md` for the version history and the
specific failure modes each version addressed.

The legacy skill name `/battle-royale` continues to work as an alias for
backward compatibility.
