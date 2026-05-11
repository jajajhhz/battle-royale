# Changelog

## v0.6 — 2026-05-11 — Any N ≥ 2 contestants

The 2-or-4 constraint was an artifact of the v0.1 hardcoded bracket logic,
not a real limit. Lifted.

### Why

The bracket is a tree, not a magic number. Single-elimination over N
contestants needs exactly N − 1 matches regardless of N, and byes for
non-powers-of-2 are a well-understood pattern from real tournament sports.
The only legitimate concerns at higher N are (a) cost — each match spawns
3 Claude subagents — and (b) signal-to-noise of the final verdict when
the bracket gets very deep. Both are warnings, not constraints.

### What changed

- **`scripts/advance.sh`** rewritten to build the bracket dynamically from
  the contestant list. Single-elimination over any N ≥ 2. Round 1 has
  `2^⌈log₂(N)⌉ − N` byes distributed to the first contestants in input
  order; every round after round 1 has a power-of-2 entry count. Round
  names follow standard tournament convention based on entry count: 2 →
  "Final", 4 → "Semifinal", 8 → "Quarterfinal", 16 → "Round of 16",
  otherwise "Round of N".

- **`scripts/quick-battle.sh`** now accepts any number of idea files ≥ 2.
  Warns at N > 16 (large run — many subagents) and refuses N > 32.
  Generated `battle.yaml` no longer hardcodes round-1 pairings; advance.sh
  builds them from contestant input order.

- **`scripts/init-battle.sh`** adds `--contestants N` (default 4, any
  N ≥ 2 supported). Stub files generated dynamically.

- **`battle.yaml` schema**: `bracket.round-1` is now the preferred key for
  explicit round-1 pairings (works at any N). The legacy `bracket.semifinals`
  key from v0.1-v0.5 is still honored for back-compat (treated as a
  round-1 override).

### Migration

- Existing v0.5 battles run unchanged — both the auto-generated YAML (no
  bracket pairings specified) and any hand-edited YAML with the legacy
  `bracket.semifinals` block continue to work.

- No defender or judge prompt changes. No rubric changes.

### Validation

End-to-end smoke tests passed for:

- **N=2:** single Final match (back-compat).
- **N=3:** 1 bye + 1 round-1 match → Final (2 matches total).
- **N=4:** Semifinal + Final (3 matches), both default pairing (1v2, 3v4)
  and legacy `semifinals:` override (1v4, 2v3).
- **N=5:** 3 byes + 1 round-1 match → Semifinal → Final (4 matches total).
- **N=8:** Quarterfinal → Semifinal → Final (7 matches total, no byes).

Each test confirmed correct round naming, correct propagation of byes
into round 2, correct winner-resolution between rounds, and the champion
declared at the end.

---

## v0.5 — 2026-05-11 — Inline mode + rename to `decision-battle-royale`

**Renames the skill** and **adds a low-friction invocation path**. No breaking
changes to the prompt or rubric layer; v0.4 verdicts remain parseable.

### Why

Two friction points emerged from real use:

1. **Setup was heavy.** Even when the user already had each option written up
   as a markdown spec, running a battle required `init-battle.sh`, then
   editing `battle.yaml` to name each contestant, then placing each spec at
   the exact filename the YAML referenced. The fastest path from "I have
   these specs" to "give me a verdict" was 6+ manual steps.

2. **The name didn't signal the use case.** `battle-royale` is memorable but
   doesn't tell first-time visitors what the skill is for. People searching
   for "decide between options with AI" or "compare ideas" had no signal
   this skill existed.

### What changed

- **New `scripts/quick-battle.sh`**: scaffolds a complete battle directory
  from 2 or 4 idea file paths passed as arguments. Auto-extracts contestant
  names from each file's `# Title` H1, drops files into a fresh dir at
  `~/Documents/battles/<slug>-<timestamp>/`, generates `battle.yaml` with a
  real bracket, and either copies the user's `--context` file or writes a
  "no shared context, lean on WebSearch" stub.

- **Skill renamed** from `battle-royale` to `decision-battle-royale`. The
  legacy `/battle-royale` slash command still works as an alias (listed in
  the SKILL.md description). The repository URL is unchanged.

- **SKILL.md describes two invocation modes**: inline (preferred — point at
  existing spec files) and scaffold-then-fill (for starting from scratch).
  The orchestrator's procedure is unchanged for both — only the path to the
  battle directory differs.

- **README rewritten** to lead with the one-line inline usage and the
  decision-making framing instead of the architecture.

### Migration

- Existing battles continue to run. The `/battle-royale` alias is still
  documented and respected.
- The default rubric, defender prompt, and judge prompt are unchanged from
  v0.4.
- To pick up v0.5, pull and re-link the skill directory under the new name:
  ```bash
  ln -s "$(pwd)/decision-battle-royale" ~/.claude/skills/decision-battle-royale
  ```

---

## v0.4 — 2026-05-09 — The Skeptic: anti-circular-context bias

**Breaking change** to judge prompt only. Defender format unchanged from v0.3.

### Why

v0.3 hid the spec from the judge but kept treating shared context as ground
truth. In practice, shared context is *authored* — it may contain interpretive
phrases ("X cannibalizes Y," "X structurally cannot ship Z," "moat through
incentive incompatibility") dressed as facts. When defender rhetoric and
shared context echo each other (a common pattern when both are synthesized
from the same upstream sources), interpretation gets laundered into
architecture. The judge sees the same phrase twice and treats it as
corroborated, even when no primary source has been checked.

Concrete example from the meishi battle: "Eight cannibalizes its feed" appeared
in both defenders' cases AND in shared context. v0.3 graded it ✓ verified
because it was "in shared context." A 30-second WebSearch under v0.4 disproved
it — Eight already ships CSV export and explicitly gates it behind their
¥600/mo Premium tier. Export is what Eight monetizes, not what they refuse to
ship. The "structural conflict" was fiction repeated until it sounded like
fact.

### What changed

- **Judge prompt**: rewritten as **The Skeptic** — a blunt, evidence-obsessed
  critic with explicit voice rules (short sentences, sharp questions, calls
  out jargon by name). The persona makes skepticism the default disposition
  rather than a reluctant tiebreaker.
- **Three-tier claim taxonomy**: every claim is now classified before being
  graded.
  - **Hard facts** (numbers, dates, named entities, public filings) →
    ✓ verifiable from shared context.
  - **Soft facts** (surveys, perceived dynamics, "informal user research")
    → ⚠ partial unless methodology is citable.
  - **Interpretive claims** ("cannibalizes," "structurally cannot ship,"
    "moat," "depends on," "creates a category," "is positioned to win")
    → **default ⚠**. Must be upgraded to ✓ via a primary source, multiple
    independent confirmations beyond shared context, OR a WebSearch result
    the judge can cite. Otherwise the grade it props up gets a **mandatory
    downgrade**.
- **Mandatory downgrade rule**: previously discretionary; now required.
  Strong with critical ⚠ → Neutral. Weak with critical ⚠ → Neutral.
- **New required output section**: `## SEARCHES PERFORMED`. Judges must
  list every WebSearch query and finding, OR explicitly state which
  interpretive claims they accepted on shared-context-only trust and why
  that's defensible.
- **Parser fix**: `scripts/parse-verdict.sh` now tolerates grade-cell
  annotations like `Neutral (DOWNGRADED from Strong)`. Judges are encouraged
  to flag downgrades inline, so the parser must accept them.

### Validation

Re-judged Match A under v0.4 using the same v0.3 defender outputs (their
one-liners and provenance tags were already correct):

| Methodology | Match A winner | Differential | Decider |
|---|---|---|---|
| v0.1 (numeric) | ① Open Meishi Capture | A: 39.5 vs B: 35.5 | numeric ceiling |
| v0.2 (grades, judge sees specs) | ① Open Meishi Capture | A: +2.5 vs B: −3.0 | spec rhetoric |
| v0.3 (grades, no spec, verification) | ③ Touch Meishi Exchange | A: −3.0 vs B: +4.0 | shared-context Wedge + Moat |
| **v0.4 (Skeptic + WebSearch verification)** | **③ Touch Meishi Exchange** | **A: −4.5 vs B: +1.0** | **Distinctiveness (untouched by downgrades)** |

Same winner as v0.3, but the **reasoning is materially different**:

- The Skeptic used 3/3 of its WebSearch budget on the load-bearing
  interpretive claim "Eight structurally cannot ship export without
  cannibalizing its feed." Primary-source verification (Eight's published
  Premium tier page) **disproved it**.
- Mandatory downgrade applied to BOTH sides' moat grades:
  - Idea B: Moat **Strong → Neutral** (the structural moat claim collapsed)
  - Idea A: Moat **Neutral → Weak** confirmed (the wedge thesis was that
    same disproved cannibalization claim, plus the spec's own "defensibility
    is thin" admission)
- The Prairie Card "1M cumulative users" anchor could not be verified beyond
  shared context within the search budget — marked ⚠.
- B still wins because **Distinctiveness** (the only grade-determining
  criterion that no interpretive claim touched) decisively favors a
  ceremonial-bilingual-buy-once iOS app with a refusal manifesto over an
  OCR scanner whose differentiator is "the absence of a feed."

The differential narrowed from +7.0 (v0.3) to +5.5 (v0.4) — the same winner,
but for a more honest reason. Three Strong grades dropped, three Weak grades
held. That's the system working: the verdict didn't flip, but the
*evidence supporting it* shifted from interpretive consensus to the one
criterion where the interpretive claims didn't matter.

### Compatibility

- Defender output format unchanged from v0.3 — defenders do NOT need to be
  re-spawned to migrate.
- Parser is backward-compatible with v0.3 verdicts (no annotations) and
  forward-compatible with v0.4 verdicts (grade-cell annotations now allowed).
- v0.3 and v0.4 verdicts can coexist in the same output tree.
- To re-judge an existing battle under v0.4: run only the judge phase with
  the new prompt; defender outputs from v0.3 stay untouched.

---

## v0.3 — 2026-05-09 — Spec-blind judge with verification

**Breaking change** to defender output format and judge architecture.

### Why

v0.2 still let spec rhetoric leak to the judge through defender quotes. A spec
that honestly enumerated risks gave its opponent free Weak-grade ammunition;
a spec that confidently asserted moats earned undeserved Strong grades from
defender interpretations the judge couldn't independently verify. Honesty was
penalized; rhetoric was rewarded. Worse, when shared context was synthesized
from the same source language as specs, evidence became circular.

The fix: the judge sees no spec content. Defenders provide a neutral one-liner
+ tag every claim with provenance (`spec` / `shared-context` / `general`).
The judge has WebSearch (limited budget) to independently verify critical
claims and discretion to downgrade unverified rhetoric.

### What changed

- **Defender prompt**: new mandatory `## ONE-LINER` section (≤30 words,
  factual, neutral) at the top of every defense — this becomes the judge's
  ONLY view of "what is this idea". All claims must be tagged with provenance
  in parentheses: `(spec)`, `(shared-context)`, or `(general)`.
- **Judge prompt**: idea names removed (judge sees only "Idea A" / "Idea B");
  shared context is now the only contextual ground truth. Judge has a
  WebSearch budget (max 3 queries per match) for verifying claims that can't
  be confirmed via shared context. Each grade carries a verification status
  (✓ verified / ⚠ partial / ✗ unverified). Judge has discretion to downgrade
  Strong → Neutral (or upgrade Weak → Neutral) when claims are critical and
  unverified.
- Output table grows the verification column; differential math unchanged.

### Validation

Re-judged the meishi battle Match A under v0.3 using the same shared-context
file. The verdict **flipped**:

| Methodology | Match A winner | Margin |
|---|---|---|
| v0.1 (numeric) | ① Open Meishi Capture | 39.5 vs 35.5 (4.0) |
| v0.2 (grades, judge sees specs) | ① Open Meishi Capture | +2.5 vs −3.0 (5.5) |
| v0.3 (grades, no spec, verification) | **③ Touch Meishi Exchange** | **+4.0 vs −3.0 (7.0)** |

Net 12.5-point grade swing. Why: ①'s Wedge dropped Strong→Weak and ①'s
Distinctiveness dropped Neutral→Weak when the judge could no longer be
persuaded by spec-quote interpretations; ③'s Wedge and Moat rose Weak→Strong
when the judge weighted shared-context-verified evidence over defender
rhetoric. The judge used 0 of 3 WebSearch queries — shared context was rich
enough for this match.

### Migration

v0.2 verdicts coexist with v0.3 verdicts in the same output tree (different
files). To re-judge under v0.3, re-spawn defenders (the new ONE-LINER section
is required) — the parser is backward-compatible with v0.2 grade tables.

---

## v0.2 — 2026-05-09 — Qualitative grading

**Breaking change** to rubric, judge prompt, and parser format.

### Why

LLMs collapse 1-10 scoring to a 6/7/8 gradient regardless of the underlying decision quality. The numeric scale created an illusion of precision while hiding the actual judgment in adjacent integers. Worse, defenders and judges could both fence-sit at "5" or "6" without committing to a position or citing evidence.

### What changed

- **Rubric (`rubrics/balanced.yaml`):** numeric `score_prompt` (1-10 anchors) replaced with `grade_anchors` describing what earns *Strong*, *Neutral*, and *Weak* grades. New top-level `grading:` block defines the three grades with point values (+1/0/−1).
- **Judge prompt (`prompts/judge.tmpl.md`):** output table changed from `| Criterion | Wt | A | B |` (numeric) to `| Criterion | Wt | A grade | A proofs | B grade | B proofs |`. Each grade requires 2+ specific quoted proofs from the spec or shared context — without them, the judge must downgrade to Neutral. Differential is computed instead of weighted total.
- **Defender prompt (`prompts/defender.tmpl.md`):** small edit to instruct defenders to argue for *Strong* grades with cited evidence, instead of arguing for "10/10".
- **Parser (`scripts/parse-verdict.sh`):** rewritten to extract grades + proofs from the new table format. Computes weighted grade differential (Σ grade_points × weight) per side. Independently recomputes math to catch judge arithmetic errors.
- **Summary (`scripts/summary.sh`):** renders grade tables with embedded proofs instead of numeric score tables.

### Migration

Existing v0.1 battles (with numeric verdicts) cannot be parsed by the v0.2 parser. To migrate: re-run the judge phase only — `battle-royale rerun --rubric balanced` — using the existing defender outputs. Defenders do NOT need to be re-spawned.

### Validation

Re-judging the meishi battle Match A under v0.2 produced the same winner (Idea ① Open Meishi Capture) as v0.1, but with:
- 4 of 5 criteria graded *Strong* or *Weak* (committed positions)
- 1 of 5 graded *Neutral* (acknowledged tie on Strategic ceiling)
- Every grade backed by 2+ specific quoted proofs from spec or shared context
- A more decisive differential (5.5-point swing vs v0.1's 4.0-point margin)
- Parser caught and silently corrected a judge arithmetic error (judge stated A:+3.5, actual A:+2.5)

### Compatibility

- Battle directory layout unchanged
- `init-battle.sh`, `advance.sh` unchanged
- v0.1 verdicts archived as `verdict.md` (numeric); v0.2 verdicts as `verdict.md` going forward (qualitative). Mixed-version output trees can coexist; the parser detects format from the verdict file.

---

## v0.1 — 2026-05-09 — Initial release

- Bash-orchestrated 4-contestant bracket
- Defenders + judge as Claude subagents (independent context per worker)
- File-based handoffs with full audit trail
- 5-criterion balanced rubric mapped to a 5-step investor decision logic
- Numeric 1-10 scoring with weighted totals
- Vanilla vs Chocolate ice cream smoke-test example
