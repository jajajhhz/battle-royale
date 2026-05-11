#!/usr/bin/env bash
# audit-verdict.sh — Parse the audit subagent's output and decide whether
#                    the verdict passes or needs a strict re-judge.
#
# Adapted from Anthropic's Bloom evals' BloomMetaJudge output schema
# (XML-tagged per-quality scores + a justification block) at
# https://github.com/safety-research/bloom — but narrowed to per-verdict
# auditing rather than suite-level meta-judgment.
#
# Usage:
#   audit-verdict.sh <audit.md> <verdict.json>
#
# Reads:
#   <audit.md>      — the audit subagent's raw output (5 XML scores +
#                     <justification> + <recommendation>)
#   <verdict.json>  — the parsed verdict this audit ran against
#
# Writes:
#   <audit.json>    — alongside audit.md: structured scores + recommendation
#
# Exit codes:
#   0  audit parsed; verdict PASSES (recommendation=PASS)
#   1  audit parsed; verdict needs RETRY (recommendation=RETRY)
#   2  audit malformed (couldn't parse all 5 scores or recommendation)
#
# The caller (advance.sh / orchestrator) uses the exit code to decide
# whether to promote the verdict or trigger a strict re-judge.

set -euo pipefail

audit_md="${1:?Usage: audit-verdict.sh <audit.md> <verdict.json>}"
verdict_json="${2:?Usage: audit-verdict.sh <audit.md> <verdict.json>}"

[[ -f "$audit_md" ]] || { echo "ERROR: audit file not found: $audit_md" >&2; exit 2; }
[[ -f "$verdict_json" ]] || { echo "ERROR: verdict.json not found: $verdict_json" >&2; exit 2; }

python3 - "$audit_md" "$verdict_json" <<'PYEOF'
import json, re, sys
from pathlib import Path

audit_path = Path(sys.argv[1])
verdict_path = Path(sys.argv[2])
out_path = audit_path.with_suffix(".json")

text = audit_path.read_text(encoding="utf-8")

# The 5 quality scores (must all parse for the audit to be valid).
QUALITIES = [
    "verification_rigor",
    "downgrade_consistency",
    "evidence_density",
    "voice_calibration",
    "search_budget_use",
]

scores = {}
missing = []
for q in QUALITIES:
    m = re.search(rf"<{q}_score>\s*(\d+)\s*</{q}_score>", text)
    if not m:
        missing.append(q)
        continue
    val = int(m.group(1))
    if val < 1 or val > 10:
        sys.stderr.write(f"ERROR: {q} score out of range [1,10]: {val}\n")
        sys.exit(2)
    scores[q] = val

if missing:
    sys.stderr.write(f"ERROR: missing audit scores: {missing}\n")
    sys.exit(2)

aggregate = sum(scores.values())
min_score = min(scores.values())

# Extract justification + recommendation blocks.
def extract_block(tag, body):
    m = re.search(rf"<{tag}>\s*(.*?)\s*</{tag}>", body, re.DOTALL)
    return m.group(1).strip() if m else ""

justification = extract_block("justification", text)
recommendation_raw = extract_block("recommendation", text)

# Recommendation logic: trust the model's PASS/RETRY only if it matches
# our threshold. The thresholds are:
#   PASS  if aggregate >= 35 AND every individual score >= 5
#   RETRY otherwise
# If the model and our thresholds disagree, log a warning and use the
# stricter outcome (RETRY wins ties).
threshold_aggregate = 35  # 5 qualities × 7 average
threshold_individual = 5

threshold_decision = (
    "PASS" if (aggregate >= threshold_aggregate and min_score >= threshold_individual)
    else "RETRY"
)

model_decision = "PASS" if "PASS" in recommendation_raw.upper() else "RETRY"

if threshold_decision != model_decision:
    sys.stderr.write(
        f"WARN: model said {model_decision} but threshold says {threshold_decision} "
        f"(aggregate={aggregate}, min={min_score}). Using stricter outcome.\n"
    )

# Stricter outcome wins. RETRY is stricter than PASS.
final_decision = "RETRY" if "RETRY" in (model_decision, threshold_decision) else "PASS"

result = {
    "scores": scores,
    "aggregate": aggregate,
    "min_score": min_score,
    "thresholds": {
        "aggregate_min": threshold_aggregate,
        "individual_min": threshold_individual,
    },
    "recommendation": final_decision,
    "model_recommendation": model_decision,
    "threshold_recommendation": threshold_decision,
    "justification": justification,
    "audited_verdict": str(verdict_path),
}

out_path.write_text(json.dumps(result, indent=2, ensure_ascii=False))

# Print human-readable summary to stderr; structured JSON to stdout.
sys.stderr.write(
    f"AUDIT  {final_decision}  aggregate={aggregate}/50  min={min_score}/10  "
    f"({audit_path.name})\n"
)
for q, v in scores.items():
    sys.stderr.write(f"  {q}: {v}/10\n")

print(json.dumps(result, ensure_ascii=False))

# Exit code: 0=PASS, 1=RETRY
sys.exit(0 if final_decision == "PASS" else 1)
PYEOF
