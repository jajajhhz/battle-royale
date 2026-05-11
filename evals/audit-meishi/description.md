# audit-meishi — Audit parser regression on the meishi v4 audit

## What this catches

`scripts/audit-verdict.sh` is the new v0.7 escalation gate. It reads the
audit subagent's XML output, extracts five quality scores, applies a
threshold, and decides PASS/RETRY. A bug in the score-extraction regex,
threshold logic, or recommendation parsing would silently let bad
verdicts through (PASS when they should RETRY) or block good ones (RETRY
when they should PASS).

This eval freezes the audit output from our v0.7 smoke test (the meishi
v4 verdict scored 36/50 with min 5 → PASS) and asserts:

- All 5 scores parse correctly (verification_rigor=6, downgrade_consistency=5,
  evidence_density=9, voice_calibration=9, search_budget_use=7)
- Aggregate = 36 (sum)
- min_score = 5 (verification_rigor and downgrade_consistency tied at 5)
- threshold_recommendation = PASS (36 ≥ 35 AND min 5 ≥ 5)
- model_recommendation = PASS (audit text contains "PASS")
- final recommendation = PASS

## Why this eval matters

The "stricter outcome wins" rule in audit-verdict.sh — RETRY beats PASS
when the model and threshold disagree — has subtle failure modes. If the
score-out-of-range check passes a 0 or 11, the threshold math breaks. If
the recommendation regex matches "RETRY" inside a paragraph that says
"don't RETRY this case," we'd get a false RETRY.

The frozen fixture is real audit output from a real subagent invocation,
not a synthetic mock — so it tests the parser against the actual format
LLMs produce, including whitespace quirks and natural language around the
XML tags.
