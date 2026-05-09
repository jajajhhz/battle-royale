# 🥊 battle-royale

**Run adversarial AI-judged contests of ideas, plans, or strategies — with structurally enforced fairness.**

A reusable Claude Code skill that compares 2 or 4 candidate ideas through a deterministic bracket. Each idea is defended by an independent Claude subagent in parallel; a separate Claude subagent judges the matchup with no shared context. The orchestrator only spawns subagents and runs scripts — it never interprets defenses or picks winners.

---

## Why this exists

When you ask an LLM "which of these ideas is best?", you get a single judgment from a single agent that has seen the whole conversation. That judgment is biased by:

- Whatever framing the orchestrator (you or your AI helper) introduced
- Order effects (the last idea discussed often wins)
- Anchoring on the most recent rhetoric
- A single-pass evaluation that doesn't pressure-test each idea adversarially

`battle-royale` enforces a different shape:

1. **Fresh-context defenders.** Each idea is defended by a separate Claude subagent that only sees its own spec, the opponent's spec, the rubric, and shared context. The defender can't see who else has been involved or what the orchestrator thinks.
2. **Adversarial debate.** Defenders are instructed to argue zealously, attack opponents' weakest rubric criteria, and sharpen their own positioning.
3. **Independent fresh-context judge.** A separate subagent reads only the rubric, shared context, and both defenses. It scores each criterion on a calibrated 1-10 scale and writes a structured verdict.
4. **Deterministic parsing.** A bash script parses the verdict via regex against the rubric's criterion names. Scores are recomputed independently — the judge's stated total isn't trusted, only its per-criterion scores.
5. **Bash-driven orchestration.** No agent decides flow; bash scripts do. Every prompt sent and every response received is saved verbatim to disk for audit.

The result: an evidence-based ranking that is reproducible, auditable, and resists orchestrator bias.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  User runs:  /battle-royale run <dir>                           │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Orchestrator (Claude in this session, following SKILL.md)     │
│                                                                 │
│   ┌────────────────────────────────────────────────────────┐    │
│   │ Phase: defenders (PARALLEL)                            │    │
│   │   - Render each defender prompt via render-prompt.sh   │    │
│   │   - Spawn N Claude subagents in parallel               │    │
│   │   - Save verbatim outputs to disk                      │    │
│   └────────────────────────────────────────────────────────┘    │
│                          │                                      │
│   ┌────────────────────────────────────────────────────────┐    │
│   │ Phase: judge                                           │    │
│   │   - Render judge prompt with both defenses + rubric    │    │
│   │   - Spawn fresh-context Claude subagent (the judge)    │    │
│   │   - Save verdict.md verbatim                           │    │
│   │   - parse-verdict.sh → verdict.json (regex, deterministic)│  │
│   │   - On parse failure: retry once with format reminder  │    │
│   └────────────────────────────────────────────────────────┘    │
│                          │                                      │
│   ┌────────────────────────────────────────────────────────┐    │
│   │ Phase: advance                                         │    │
│   │   - Read all match verdicts                            │    │
│   │   - Determine winners deterministically                │    │
│   │   - Write next-round bracket or mark complete          │    │
│   └────────────────────────────────────────────────────────┘    │
│                          │                                      │
│   ┌────────────────────────────────────────────────────────┐    │
│   │ Phase: summary                                         │    │
│   │   - Walk output tree, render markdown report           │    │
│   └────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

**Key invariant:** the orchestrator never reads defender content or interprets judge content. It only spawns subagents and runs bash scripts. This is what eliminates orchestrator bias structurally.

---

## Installation

This is a Claude Code skill. Install by symlinking or copying into `~/.claude/skills/`:

```bash
git clone https://github.com/jajajhhz/battle-royale.git
ln -s "$(pwd)/battle-royale" ~/.claude/skills/battle-royale
chmod +x battle-royale/scripts/*.sh
```

Verify it's installed:

```bash
ls ~/.claude/skills/battle-royale/SKILL.md
```

In your next Claude Code session, the `battle-royale` skill should be discoverable via the Skill tool.

### Requirements

- macOS or Linux
- `bash` 4+
- `python3` (for YAML/regex parsing in scripts)
- Claude Code (the orchestrator runs inside Claude Code; defenders and judges are spawned via the Agent tool)

---

## Usage

### Quick start: run a battle from scratch

```bash
# 1. Scaffold a battle directory
bash ~/.claude/skills/battle-royale/scripts/init-battle.sh ~/work/my-battle --name "My Decision"

# 2. Edit the battle
vim ~/work/my-battle/battle.yaml          # set contestant names, pairings
vim ~/work/my-battle/ideas/idea-1.md      # write each contestant's full spec
vim ~/work/my-battle/ideas/idea-2.md
vim ~/work/my-battle/ideas/idea-3.md
vim ~/work/my-battle/ideas/idea-4.md
vim ~/work/my-battle/context/shared-context.md  # market evidence + competitor table

# 3. From Claude Code, invoke the skill
# /battle-royale run ~/work/my-battle
```

### Or try the included smoke test

```bash
# From Claude Code:
# /battle-royale run ~/.claude/skills/battle-royale/examples/vanilla-vs-chocolate
```

The smoke test runs a 2-contestant battle (Vanilla vs Chocolate ice cream) end-to-end in ~3 minutes and verifies every component works.

### Commands

```
/battle-royale init <dir> [--name "Name"] [--rubric balanced]
    Scaffold a new battle directory with template files

/battle-royale run [<dir>]
    Run a battle end-to-end (defenders → judge → advance → summary)

/battle-royale rerun <dir> --rubric <new>
    Re-judge existing defender outputs under a different rubric.
    Cheap rubric-sensitivity test — defenders are NOT re-spawned.

/battle-royale status [<dir>]
    Show current state (which round, which matches pending)

/battle-royale summary [<dir>]
    Render the final report
```

---

## The default rubric

The included `rubrics/balanced.yaml` evaluates ideas against a 5-step investor decision logic:

| Step | Criterion | Weight |
|---|---|---|
| 1 — Category & ceiling | Strategic ceiling | 1.5 |
| 2 — Wedge & traction | Wedge & market evidence | 1.5 |
| 3+4 — Architecture & moat + Trust | Moat & trust posture | 1.5 |
| (cross-cutting) | Distinctiveness | 1.0 |
| 5 — Execution credibility | Execution credibility | 1.0 |

Total weight: 6.5. Maximum score: 65 per match.

Each criterion has a calibrated 1/4/7/10 anchor scale that defines what each score means. This prevents drift across judges and runs.

You can author your own rubric by dropping a YAML file in `rubrics/` matching the schema. See `rubrics/balanced.yaml` for the exact structure.

---

## File layout

```
battle-royale/
├── SKILL.md                    # Claude Code skill definition (procedural orchestration)
├── README.md                   # this file (humans)
├── LICENSE                     # MIT
├── prompts/
│   ├── defender.tmpl.md        # defender prompt template ({PLACEHOLDERS})
│   └── judge.tmpl.md           # judge prompt template
├── rubrics/
│   └── balanced.yaml           # default 5-criterion rubric
├── scripts/
│   ├── render-prompt.sh        # substitute placeholders from env vars (Python-backed)
│   ├── parse-verdict.sh        # regex-extract scores from judge verdict → JSON
│   ├── advance.sh              # determine winners, write next-round config
│   ├── summary.sh              # generate final markdown report
│   └── init-battle.sh          # scaffold a new battle directory
└── examples/
    └── vanilla-vs-chocolate/   # 2-contestant smoke test (ice cream)
        ├── battle.yaml
        ├── ideas/
        ├── context/
        └── (output/ created at runtime)
```

A user-created battle directory looks like:

```
my-battle/
├── battle.yaml                 # config (contestants, rubric, format, pairings)
├── ideas/
│   ├── idea-1.md               # full spec for contestant 1
│   ├── idea-2.md
│   └── ...
├── context/
│   └── shared-context.md       # market evidence, competitor table
└── output/                     # generated; auditable; do not edit by hand
    ├── meta.json
    ├── state.json
    ├── round-1/
    │   ├── bracket.json
    │   └── match-A/
    │       ├── prompts/        # exact prompts sent to subagents
    │       ├── defender-1.md   # subagent outputs (verbatim)
    │       ├── defender-3.md
    │       ├── verdict.md      # judge's raw output
    │       └── verdict.json    # parsed scores
    └── final-report.md
```

---

## How it differs from naive AI ranking

| Naive approach | battle-royale |
|---|---|
| Single AI judges all ideas in one pass | Separate AI defenders + separate fresh-context judge per match |
| Ranking happens in conversation context | Ranking happens via deterministic bash scripts on saved files |
| Order effects bias the result | Each defender sees only its spec + opponent's spec |
| Can't tell why an idea won | Every prompt and response is saved; criterion-by-criterion scores explain the verdict |
| Rubric drifts mid-evaluation | Rubric is a YAML file with calibrated 1/4/7/10 anchors |
| Re-running with a tweaked rubric requires regenerating everything | `rerun` re-judges existing defenses without re-spawning defenders |
| Rhetoric beats evidence | Judges are required to cite shared context for market/moat criteria |

---

## Adapted from the harness pattern

This skill is modeled on Anthropic's [harness design pattern for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps), adapted for adversarial decision-making. The harness pattern's core principles — fresh context for evaluation, file-based handoffs, deterministic orchestration — translate directly to a battle royale where:

- **Generator** → **Defender** (zealously argues for one idea)
- **Evaluator** → **Judge** (scores against a calibrated rubric)
- **Sprint contract** → **Match** (which two ideas, which rubric)
- **Loop until pass** → **Single-shot per match** (winner declared, advance bracket)

If you build implementation harnesses, this is the same architectural shape applied to product/strategy decisions instead of code shipping.

---

## Contributing

Author your own rubric in `rubrics/`, follow the schema in `balanced.yaml`. Different decision domains benefit from different criteria — code review choices, vendor selection, hiring panel simulation, architectural decisions all have their own structure.

PRs welcome for:
- Additional rubrics (with calibrated anchors)
- Bracket size variants (currently 2 or 4 contestants; 8 is a natural extension)
- Output renderers (HTML report, CSV scoreboard, etc.)
- All-vs-all format alongside the bracket format

---

## License

MIT. See `LICENSE`.
