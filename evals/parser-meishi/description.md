# parser-meishi — Parser regression on the meishi v4 verdict

## What this catches

`scripts/parse-verdict.sh` is the load-bearing piece of the orchestration
pipeline. Every downstream consumer (advance.sh, audit-verdict.sh,
summary.sh) reads the parsed JSON, not the verdict markdown. If the parser
regresses, every consumer gets stale data and the audit phase can score
incorrectly.

This eval freezes the meishi battle Match A v4 verdict (a real production
output from our v0.4 validation pass) and asserts that the parser extracts:

- The correct winner (`B`)
- All 5 grade rows with correct grade values
- The expected differential (`A: -4.5`, `B: +1.0`)
- The `SEARCHES PERFORMED` section parsed into 3 structured queries (v0.8
  added this field — regression-protect it from removal)
- The reasoning, deciding factor, and ceiling-risk sections

## Why this eval matters

v0.7's audit phase scores `search_budget_use` based on the parsed
verdict's `searches_performed` field. If that field disappears or
miscounts queries, the audit blind-scores it as 0 and triggers spurious
RETRY runs.

The eval also documents the v0.4 verdict structure so anyone modifying
`parse-verdict.sh` has a concrete regression target.
