# Eval suite — `evals/`

A library of ground-truth tests that gate every release. Without this, every
"performance improvement" is a guess.

## Why

Prior to v0.8, the only validation pattern was: change the prompt, re-run
the meishi battle, eyeball the verdict. That's not a measurable signal —
two well-meaning changes that *each* improve quality might individually
pass eyeball-check but interact badly. Without a frozen test suite, we
can't tell.

This directory contains evals. Each eval is a directory with:

- An `expected.json` describing the assertions
- A `description.md` explaining what failure mode it tests for
- A `fixtures/` directory with the frozen inputs (verdicts, audits,
  prompts, etc.) the assertions run against
- Optionally `manual: true` in expected.json if it requires a live
  subagent run (excluded from the default suite, run on demand)

## How to run

```bash
bash scripts/eval-suite.sh                      # run all auto evals, write EVAL_RESULTS.md
bash scripts/eval-suite.sh --eval <name>        # run one eval only
bash scripts/eval-suite.sh --include-manual     # also run live-subagent evals
```

The runner writes [`EVAL_RESULTS.md`](../EVAL_RESULTS.md) at the repo root —
that file is committed and shows the version-by-version pass/fail matrix.
Anyone evaluating the skill before adopting can see "v0.8 passes 7/9
evals" without running anything.

## Categories

| Category | What it tests | How |
|---|---|---|
| `parser` | `scripts/parse-verdict.sh` extracts the right fields from a verdict.md | Frozen-fixture regression |
| `audit` | `scripts/audit-verdict.sh` parses + thresholds correctly | Frozen-fixture regression |
| `injection` | Defender / judge prompts wrap user content in delimiters | Structural — render the prompt, grep for delimiter strings |
| `frontmatter` | SKILL.md frontmatter is spec-compliant (name, description, license) | Parse + assert fields |
| `smoke` | The full pipeline produces a parseable verdict on the included example | Live subagent run (manual) |
| `bias` | Misleading shared-context claims trigger WebSearch / downgrade | Live subagent run (manual) |

## Adding an eval

1. Create `evals/<your-eval-name>/`
2. Write `description.md` explaining the failure mode you want to catch
3. Put frozen inputs (if any) under `fixtures/`
4. Write `expected.json` with the assertions (schema below)
5. Run `bash scripts/eval-suite.sh --eval <your-eval-name>` to verify
6. Commit. The eval is now part of the suite.

## `expected.json` schema

```json
{
  "name": "human-readable name",
  "category": "parser | audit | injection | frontmatter | smoke | bias",
  "manual": false,
  "assertions": [
    {
      "type": "parser_extracts",
      "fixture": "fixtures/verdict.md",
      "rubric": "rubrics/balanced.yaml",
      "expect": {
        "winner": "B",
        "searches_count": 3,
        "grades.strategic_ceiling.a_grade": "Weak"
      }
    },
    {
      "type": "audit_recommendation",
      "audit_fixture": "fixtures/audit.md",
      "verdict_fixture": "fixtures/verdict.json",
      "expect": {
        "recommendation": "PASS",
        "aggregate_min": 30,
        "scores.verification_rigor_min": 5
      }
    },
    {
      "type": "rendered_prompt_contains",
      "template": "prompts/defender.tmpl.md",
      "env": {
        "IDEA_SPEC": "(spec content)",
        "OPPONENT_SPEC": "(opponent content)",
        "SHARED_CONTEXT": "(context content)"
      },
      "expect": {
        "contains_all": [
          "════════════════ DOCUMENT START ════════════════",
          "════════════════ DOCUMENT END ════════════════"
        ]
      }
    },
    {
      "type": "frontmatter_valid",
      "file": "SKILL.md",
      "expect": {
        "name": "decision-battle-royale",
        "has_license": true,
        "description_max_chars": 1024
      }
    }
  ]
}
```

Each assertion's `type` corresponds to a check function in
`scripts/eval-suite.sh`. New assertion types are easy to add — the runner
dispatches on `type` and each check function returns pass/fail + a
human-readable message.
