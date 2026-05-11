# 🥊 Decision Battle Royale

**Decide between 2 or more ideas, plans, or strategies — by having independent fresh-context AI agents argue and judge them for you.**

A [Claude Code](https://claude.com/claude-code) skill (`/decision-battle-royale`) that turns "which option should I pick?" into a structured tournament: each option gets its own zealous AI advocate, then a *separate* AI judge with no prior context picks a winner using a calibrated rubric and primary-source verification.

Use it when you're stuck between options and want a **second opinion that isn't biased by the conversation you've already had.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Skill: Claude Code](https://img.shields.io/badge/skill-Claude_Code-purple.svg)](https://docs.claude.com/en/docs/claude-code)
[![Version](https://img.shields.io/badge/version-v0.5-blue.svg)](CHANGELOG.md)

---

## Why you'd want this

You've been brainstorming with Claude. Now you have a handful of candidate ideas — product directions, architectural choices, naming options, vendor shortlists, hiring final-rounds, anything. You ask "which is best?" and get a confident answer.

**The problem:** that answer is from the same session that helped you generate the ideas. It's already anchored to your framing, the last thing you said, and whatever rhetoric stuck around.

**What `decision-battle-royale` does instead:**

1. Spawns a fresh Claude subagent for **each option** to defend it adversarially — they only see their own spec, the opponent's spec, and shared context. Not your conversation.
2. Spawns a *separate* fresh judge subagent with no spec access — it only sees what defenders surface. The judge has WebSearch and a strict mandate to verify interpretive claims against primary sources.
3. Records every prompt and response to disk. The orchestrator (the session you're talking to) **cannot read the defenses or the verdict** — only spawn the agents and run parse scripts. Bias is structurally impossible.

The result: a defensible, auditable verdict for a decision that matters.

---

## Use it in one line

Once installed, just pass the markdown files for each option directly to the slash command:

```text
/decision-battle-royale decide between ~/specs/option-a.md and ~/specs/option-b.md
```

That's it. The skill auto-extracts contestant names from the file titles, scaffolds a battle directory, spawns the defenders in parallel, spawns the skeptical judge, and reports the verdict — all without you authoring a `battle.yaml` or filling in stub files.

**Any number of contestants is supported.** With five options and shared market context:

```text
/decision-battle-royale battle these: a.md b.md c.md d.md e.md
context is market-research.md, name it "Q3 product launch options"
```

The bracket auto-builds: 5 contestants → 1 round-1 match (2 contestants play, 3 get byes) → Semifinal → Final. 4 matches total to crown a winner. Any N ≥ 2 works (the tool refuses N > 32 and warns at N > 16 because cost scales linearly).

The skill responds to natural language — *"compare these specs,"* *"which option is best,"* *"have agents debate these,"* *"second opinion on which to pick"* — not just the literal slash command.

---

## What you get

A real verdict from a head-to-head match between two product ideas:

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
Both sides leaned on the same load-bearing claim ("Eight cannibalizes its
feed"). WebSearch killed it. Mandatory downgrade applied. B still wins —
not because the moat held, but because Distinctiveness is the only grade
the verification machinery didn't touch...
```

Every grade is backed by specific quoted proofs. Every WebSearch query is logged. Every prompt and response is saved verbatim to disk so you can audit *why* the verdict went the way it did.

---

## Install (one-time)

```bash
git clone https://github.com/jajajhhz/battle-royale.git decision-battle-royale
ln -s "$(pwd)/decision-battle-royale" ~/.claude/skills/decision-battle-royale
chmod +x decision-battle-royale/scripts/*.sh
```

In your next Claude Code session the skill is auto-discoverable as `/decision-battle-royale` (the legacy `/battle-royale` alias still works).

### Try the smoke test

```text
/decision-battle-royale run ~/.claude/skills/decision-battle-royale/examples/vanilla-vs-chocolate
```

Runs a 2-contestant ice-cream battle end-to-end in ~3 minutes. Verifies install and shows you what a full output tree looks like.

---

## Two ways to run a battle

### 1. **Inline mode** — fastest, recommended

You already have each option written up as a `.md` file. Just point the skill at them:

```text
/decision-battle-royale ~/specs/idea-a.md ~/specs/idea-b.md
```

The skill calls `quick-battle.sh` under the hood to:
- Pull contestant names from each file's `# Title` header
- Drop the files into a fresh battle dir at `~/Documents/battles/<slug>-<timestamp>/`
- Run the full pipeline

Optional inline flags (the skill recognizes them in natural language too):
- `--context <ctx.md>` — shared market evidence the judge will ground claims in (otherwise the judge leans entirely on WebSearch)
- `--name "Title"` — what to call the battle in the final report
- `--rubric balanced` — which rubric to use (default `balanced`)

### 2. **Scaffold-then-fill mode** — when starting from scratch

If you don't have the option specs written yet:

```text
/decision-battle-royale init ~/work/my-decision --name "Q3 launch"
```

Creates stub idea files and a `battle.yaml` for you to fill in. Then run:

```text
/decision-battle-royale run ~/work/my-decision
```

---

## When to use this

**Good fits:**
- Picking between 2-8 product directions (any N ≥ 2 works; cost grows linearly)
- Architectural decisions with clear trade-offs (monolith vs microservices, framework A vs B)
- Naming, branding, or positioning options
- Vendor shortlists
- Hiring final-round comparisons
- Any decision where "ask Claude" and "ask Codex/Gemini" give different answers and you want a structured tiebreaker

**Not a fit:**
- Single-option go/no-go decisions (use a planning tool)
- Decisions with >16 candidates — cost grows linearly and the verdict signal-to-noise drops; cull your shortlist first (the tool refuses >32)
- Decisions where you want a full ranking rather than a single winner — single-elimination only picks one champion
- Decisions where you don't have written specs for each option (write them first — the act of writing is often what reveals the winner)

Natural-language invocations the skill responds to: *"decide between these,"* *"which option is best,"* *"compare these ideas,"* *"second opinion on which to pick,"* *"battle these specs,"* *"have agents debate."*

---

## How it differs from just asking Claude

| Naive approach (ask Claude in your session) | decision-battle-royale |
|---|---|
| One AI judges all options in one pass | Separate AI defenders + separate fresh-context judge per match |
| Judgment happens in your conversation context | Judgment happens in independent subagents — your framing can't leak |
| Order effects bias the result | Each defender sees only its spec + the opponent's spec |
| You can't tell why an idea won | Every prompt and response is saved; criterion-by-criterion grades with cited proofs explain the verdict |
| Rhetoric beats evidence | Judge defaults to "unverified" on interpretive claims; primary-source WebSearch is required to upgrade to "verified"; unverified claims trigger mandatory grade downgrades |
| Re-running with a tweaked rubric requires redoing everything | `rerun` re-judges existing defenses without re-spawning defenders |

---

## The default rubric

`rubrics/balanced.yaml` evaluates ideas against a 5-step decision logic borrowed from investor evaluation patterns:

| Criterion | Weight | What it measures |
|---|---|---|
| Strategic ceiling | 1.5 | Is the category big enough? Direct comps at the exact thesis? |
| Wedge & market evidence | 1.5 | Sharp narrow entry + validated demand + competitor gap incumbents won't fill |
| Moat & trust posture | 1.5 | Multiple compounding moats OR a structural moat incumbents architecturally cannot copy |
| Distinctiveness | 1.0 | Memorable refusal manifesto, defining design choices, passes the show-stranger-24h test |
| Execution credibility | 1.0 | Solo-buildable with founder's existing skills, kill-gates defined |

Each criterion is graded **Strong (+1)** / **Neutral (0)** / **Weak (−1)** with 2+ specific quoted proofs required. Differential = Σ (grade × weight). Higher wins.

**Authoring your own rubric:** drop a YAML file in `rubrics/` matching the schema in `balanced.yaml`. Different decisions need different criteria — code reviews, vendor selection, hiring panels, naming, architectural choices all have natural rubric structures.

---

## The skeptical judge (v0.4)

In v0.4 the judge persona was rewritten as **"The Skeptic"** — a blunt, evidence-obsessed critic with explicit voice rules:

- Treats shared context as **authored and possibly biased**, not ground truth
- Defaults every interpretive claim ("X cannibalizes Y," "X structurally cannot ship Z," "X has a moat") to **⚠ partial verification**
- Must earn **✓ verified** via primary source, multiple independent confirmations, or WebSearch (≤3 queries per match)
- **Mandatory downgrade rule**: if a critical interpretive claim is unverifiable, the grade it props up drops one level (Strong→Neutral, Weak→Neutral)

This catches a common failure mode where defender rhetoric and synthesized "shared context" repeat the same interpretive phrase ("X cannibalizes its feed"), and the judge treats the echo as corroboration. v0.4's validation pass on a real product battle showed WebSearch disproving exactly this kind of laundered claim — same verdict survived, but for a more honest reason.

See [CHANGELOG.md](CHANGELOG.md) for the full evolution.

---

## File layout

```
decision-battle-royale/
├── SKILL.md                    # Claude Code skill definition
├── README.md                   # this file
├── CHANGELOG.md                # v0.1 → v0.5 evolution
├── prompts/
│   ├── defender.tmpl.md        # zealous-advocate prompt
│   └── judge.tmpl.md           # The Skeptic prompt
├── rubrics/
│   └── balanced.yaml           # 5-criterion default rubric
├── scripts/                    # bash orchestration (deterministic)
│   ├── quick-battle.sh         # one-shot scaffold from inline paths ← NEW in v0.5
│   ├── init-battle.sh          # stub-file scaffold for from-scratch decisions
│   ├── render-prompt.sh
│   ├── parse-verdict.sh
│   ├── advance.sh
│   └── summary.sh
└── examples/
    └── vanilla-vs-chocolate/   # 2-contestant smoke test
```

A user-created decision looks like:

```
my-decision/
├── battle.yaml                 # config — contestants, rubric, format (auto-generated in inline mode)
├── ideas/idea-{1..4}.md        # one spec per option (you write these)
├── context/shared-context.md   # market evidence (optional)
└── output/                     # generated; never edit by hand
    ├── state.json
    ├── round-1/match-A/
    │   ├── defender-1.md       # zealous defense (verbatim subagent output)
    │   ├── defender-2.md
    │   ├── verdict.md          # judge's reasoned verdict
    │   └── verdict.json        # parsed grades + differential
    └── final-report.md
```

---

## Requirements

- macOS or Linux
- `bash` 4+
- `python3` (for YAML / regex parsing inside scripts)
- [Claude Code](https://claude.com/claude-code) (the orchestrator runs inside Claude Code; defenders and judges are spawned via the Agent tool)

---

## Inspired by the harness pattern

This skill is modeled on Anthropic's [harness design pattern for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps), adapted for adversarial decision-making:

- **Generator → Defender** (zealously argues for one option)
- **Evaluator → Judge** (grades against the rubric, verifies via WebSearch)
- **Fresh context for evaluation** — the session that helped generate doesn't judge

If you build implementation harnesses, this is the same architectural shape applied to product, strategy, and architectural decisions instead of code shipping.

---

## Contributing

PRs welcome for:

- **New rubrics** (with calibrated Strong/Neutral/Weak anchors) — naming, architectural choices, vendor selection, hiring panels all benefit from purpose-built rubrics
- **Output renderers** — HTML reports, CSV scoreboards, Slack-friendly summaries
- **Bracket size variants** — 8-contestant bracket, double-elimination
- **All-vs-all format** — alongside the current bracket format

---

## License

MIT. See [LICENSE](LICENSE).
