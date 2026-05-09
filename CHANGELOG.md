# Changelog

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
