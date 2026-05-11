# 🥊 Decision Battle Royale

**Decide between 2 or more ideas with a tournament of independent AI judges.**

Each option gets its own AI advocate. A separate judge — with no access to your conversation — picks the winner using a calibrated rubric and WebSearch fact-checking. A third audit subagent scores the verdict and forces a strict re-judge if quality is low.

The orchestrator never reads the defenses or verdicts. Your framing cannot bias the result.

[![Eval suite](https://github.com/jajajhhz/battle-royale/actions/workflows/evals.yml/badge.svg)](https://github.com/jajajhhz/battle-royale/actions/workflows/evals.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skill: Claude Code](https://img.shields.io/badge/skill-Claude_Code-purple.svg)](https://docs.claude.com/en/docs/claude-code)

---

## Quick example

Pass your idea files directly:

```text
/decision-battle-royale decide between ~/specs/option-a.md and ~/specs/option-b.md
```

The skill auto-extracts contestant names from the files' titles, scaffolds a battle directory, spawns the defenders in parallel, runs the judge, audits the verdict, and reports the winner — all in one command.

It also responds to natural language: *"compare these specs,"* *"which option is best,"* *"second opinion on which to pick,"* *"have agents debate these."*

---

## What you get

A verdict markdown table with criterion-by-criterion grades, every claim backed by quoted proofs and verified via WebSearch:

```
## VERDICT: Idea B wins

| Criterion              | Wt  | Idea A | Idea B |
|------------------------|-----|--------|--------|
| 1. Strategic ceiling   | 1.5 | Weak   | Neutral|
| 2. Wedge & market      | 1.5 | Weak   | Neutral|
| 3. Moat & trust        | 1.5 | Weak   | Neutral (DOWNGRADED — see below) |
| 4. Distinctiveness     | 1.0 | Weak   | Strong |
| 5. Execution           | 1.0 | Strong | Neutral|
| DIFFERENTIAL           |     | -4.5   | +1.0   |

## SEARCHES PERFORMED
Query: "Eight 8card business export feature pricing" → Finding: Eight already
gates CSV export behind ¥600/mo Premium tier. The "structural cannibalization"
claim that propped up both sides' moat collapses under primary-source check.

## REASONING
Both sides leaned on the same load-bearing claim. WebSearch killed it.
Mandatory downgrade applied. B still wins — not because the moat held,
but because Distinctiveness is the only grade the verification machinery
didn't touch...
```

Every prompt and response is saved to disk. Every WebSearch query is logged. Full audit trail for replay.

---

## Install

```bash
git clone https://github.com/jajajhhz/battle-royale.git decision-battle-royale
ln -s "$(pwd)/decision-battle-royale" ~/.claude/skills/decision-battle-royale
chmod +x decision-battle-royale/scripts/*.sh
```

In your next [Claude Code](https://claude.com/claude-code) session the skill is auto-discoverable.

Try the smoke test (3 minutes):

```text
/decision-battle-royale run ~/.claude/skills/decision-battle-royale/examples/vanilla-vs-chocolate
```

---

## Use it

### Two ways to run a battle

**Inline mode** — when you already have spec files:

```text
/decision-battle-royale ~/specs/idea-a.md ~/specs/idea-b.md
```

Any number of ideas ≥ 2 works. With four contestants and shared market context:

```text
/decision-battle-royale battle these: a.md b.md c.md d.md
context is market-research.md, name it "Q3 product launch options"
```

The bracket auto-builds: 5 contestants → 1 round-1 match + 3 byes → Semifinal → Final.

**Scaffold mode** — when starting from scratch:

```text
/decision-battle-royale init ~/work/my-decision --contestants 4
```

Creates stub idea files for you to fill in. Then `run` when ready.

---

## When to use this

**Good fits:**
- Picking between 2-8 product directions
- Architectural trade-offs (framework A vs B, monolith vs microservices, SQL vs NoSQL)
- Naming, branding, or positioning options
- Vendor shortlists
- Hiring final-round comparisons
- Any decision where "ask Claude" and "ask Codex/Gemini" give different answers

**Not a fit for:**
- Single-option go/no-go decisions
- Decisions with >16 candidates (cull your shortlist first)
- Decisions where you don't have written specs (write them first — the act of writing often reveals the answer)

---

## How it works

Three independent fresh-context Claude subagents per match:

1. **Defenders** — one per option, each only sees its own spec and the opponent's spec. They argue zealously for their option. Defenders write their case to disk; the orchestrator never reads it.
2. **Judge** — a skeptical critic with WebSearch budget. Treats interpretive claims ("cannibalizes," "structurally cannot ship") as unverified by default; must earn ✓ verified via primary source. Unverified critical claims trigger mandatory grade downgrades.
3. **Audit** — scores the judge's verdict on 5 quality axes (verification rigor, downgrade consistency, evidence density, voice calibration, search-budget use). If aggregate falls below threshold, a strict re-judge runs with tighter requirements.

Orchestration is bash-driven and deterministic. Bracket advancement, parsing, and reporting are pure scripts. The Claude session you're talking to spawns subagents and runs scripts — it never reads what they produce. That's what makes bias structurally impossible.

---

## The rubric

Five criteria, each graded **Strong** (+1) / **Neutral** (0) / **Weak** (−1) with 2+ cited proofs required:

| Criterion | Weight | What it measures |
|---|---|---|
| Strategic ceiling | 1.5 | Is the category big enough? Direct comps at this thesis? |
| Wedge & market evidence | 1.5 | Sharp narrow entry + validated demand + competitor gap |
| Moat & trust posture | 1.5 | Compounding moats OR structural conflicts incumbents can't fix |
| Distinctiveness | 1.0 | Memorable refusal manifesto, can't be confused with alternatives |
| Execution credibility | 1.0 | Solo-buildable with kill-gates defined |

**Custom rubrics:** drop a YAML file in `rubrics/` matching `balanced.yaml`. Different decisions deserve different criteria — code reviews, vendor selection, hiring panels, architectural choices all benefit from purpose-built rubrics.

---

## Reliability

The skill ships with an automated eval suite (`scripts/eval-suite.sh`) that gates every release. GitHub Actions runs the suite on every push — the badge above shows the live state of `main`. See [`evals/`](evals/) for the test fixtures and [`EVAL_RESULTS.md`](EVAL_RESULTS.md) for the latest report.

Categories tested today:
- Parser regression (every grade, every search query)
- Audit threshold / escalation logic
- Prompt injection delimiters
- SKILL.md spec compliance (frontmatter, description length, trigger phrases)
- Template rendering hygiene

---

## File layout

```
decision-battle-royale/
├── SKILL.md                # skill definition for Claude Code
├── prompts/                # subagent prompt templates
├── rubrics/                # grading rubrics (YAML)
├── scripts/                # bash orchestration + parsers
├── evals/                  # ground-truth tests for the eval suite
└── examples/               # smoke test (vanilla-vs-chocolate)
```

A user-created battle:

```
my-decision/
├── battle.yaml             # config (auto-generated in inline mode)
├── ideas/idea-{1..N}.md    # your spec per option
├── context/shared-context.md  # market evidence (optional)
└── output/                 # all prompts + responses + parsed verdicts
    ├── state.json
    ├── round-*/match-*/    # defender outputs, verdict, audit
    └── final-report.md
```

---

## Requirements

macOS or Linux. `bash` 4+, `python3`, [Claude Code](https://claude.com/claude-code).

---

## Contributing

Custom rubrics and output renderers are the most-wanted contributions. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for details (coming soon — for now, open an issue or PR).

---

## License

MIT. See [LICENSE](LICENSE).
