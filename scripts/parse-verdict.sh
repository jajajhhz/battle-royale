#!/usr/bin/env bash
# parse-verdict.sh — Extract structured scores from a judge verdict.md
#
# Usage:
#   parse-verdict.sh <verdict.md> <rubric.yaml>
#
# Output: JSON with keys:
#   {
#     "verdict": "Idea A" | "Idea B",
#     "scores": {
#       "criterion_id": { "a": int, "b": int, "weight": float }
#     },
#     "weighted_total_a": float,
#     "weighted_total_b": float,
#     "winner": "A" | "B",
#     "deciding_factor": "...",
#     "ceiling_risk": "..."
#   }
#
# Exit codes:
#   0  parsed cleanly
#   2  format error (missing scores, malformed table)
#   3  scores out of range or non-integer

set -euo pipefail

verdict="${1:?Usage: parse-verdict.sh <verdict.md> <rubric.yaml>}"
rubric="${2:?Usage: parse-verdict.sh <verdict.md> <rubric.yaml>}"

[[ -f "$verdict" ]] || { echo "ERROR: verdict not found: $verdict" >&2; exit 1; }
[[ -f "$rubric" ]] || { echo "ERROR: rubric not found: $rubric" >&2; exit 1; }

python3 - "$verdict" "$rubric" <<'PYEOF'
import json, re, sys
from pathlib import Path

verdict_path = Path(sys.argv[1])
rubric_path = Path(sys.argv[2])

verdict_text = verdict_path.read_text(encoding="utf-8")

# Load rubric criteria (lightweight YAML parsing — top-level criteria list)
rubric_text = rubric_path.read_text(encoding="utf-8")
criteria = []
current = None
for line in rubric_text.splitlines():
    s = line.rstrip()
    m_id = re.match(r"\s*- id:\s*(\S+)", s)
    if m_id:
        if current:
            criteria.append(current)
        current = {"id": m_id.group(1)}
        continue
    m_name = re.match(r"\s+name:\s*\"([^\"]+)\"", s)
    if m_name and current is not None:
        current["name"] = m_name.group(1)
        continue
    m_weight = re.match(r"\s+weight:\s*([0-9.]+)", s)
    if m_weight and current is not None:
        current["weight"] = float(m_weight.group(1))
        continue
if current:
    criteria.append(current)

if not criteria:
    sys.stderr.write("ERROR: no criteria parsed from rubric\n")
    sys.exit(2)

# Parse verdict line
verdict_match = re.search(r"##\s*VERDICT:\s*Idea\s*([AB])\b", verdict_text, re.IGNORECASE)
if not verdict_match:
    sys.stderr.write("ERROR: no VERDICT line found\n")
    sys.exit(2)
winner_letter = verdict_match.group(1).upper()

# Parse score table — match each criterion row
# Row format: | N. Criterion Name | weight | A/10 | B/10 |
scores = {}
for crit in criteria:
    name = crit["name"]
    # Match the row containing the criterion name
    # Tolerate variations in spacing
    pattern = (
        r"\|\s*\d+\.\s*"
        + re.escape(name)
        + r"\s*\|\s*([0-9.]+)\s*\|\s*(\d+)\s*/\s*10\s*\|\s*(\d+)\s*/\s*10\s*\|"
    )
    m = re.search(pattern, verdict_text, re.IGNORECASE)
    if not m:
        sys.stderr.write(f"ERROR: could not parse score row for criterion: {name}\n")
        sys.exit(2)
    weight_in_table = float(m.group(1))
    a_score = int(m.group(2))
    b_score = int(m.group(3))
    if not (1 <= a_score <= 10 and 1 <= b_score <= 10):
        sys.stderr.write(f"ERROR: scores out of range 1-10 for {name}: a={a_score} b={b_score}\n")
        sys.exit(3)
    # Validate weight matches rubric (warn only)
    if abs(weight_in_table - crit["weight"]) > 0.01:
        sys.stderr.write(
            f"WARN: weight mismatch for {name}: rubric={crit['weight']} table={weight_in_table}\n"
        )
    scores[crit["id"]] = {
        "name": name,
        "weight": crit["weight"],
        "a": a_score,
        "b": b_score,
    }

weighted_a = round(sum(s["a"] * s["weight"] for s in scores.values()), 1)
weighted_b = round(sum(s["b"] * s["weight"] for s in scores.values()), 1)

# Determine winner from scores; cross-check with stated VERDICT
score_winner = "A" if weighted_a > weighted_b else "B" if weighted_b > weighted_a else "TIE"
if score_winner != "TIE" and score_winner != winner_letter:
    sys.stderr.write(
        f"WARN: stated verdict ({winner_letter}) disagrees with score winner ({score_winner})\n"
    )

# Extract deciding factor and ceiling/risk paragraphs
def extract_section(text, header):
    pattern = rf"##\s*{re.escape(header)}\s*\n+(.*?)(?=\n##\s|\Z)"
    m = re.search(pattern, text, re.DOTALL | re.IGNORECASE)
    return m.group(1).strip() if m else ""

deciding_factor = extract_section(verdict_text, "THE DECIDING FACTOR")
ceiling_risk = extract_section(verdict_text, "CEILING × RISK ASSESSMENT") or extract_section(
    verdict_text, "CEILING x RISK ASSESSMENT"
)
reasoning = extract_section(verdict_text, "REASONING")

result = {
    "verdict": f"Idea {winner_letter}",
    "winner": winner_letter,
    "scores": scores,
    "weighted_total_a": weighted_a,
    "weighted_total_b": weighted_b,
    "score_winner": score_winner,
    "deciding_factor": deciding_factor,
    "ceiling_risk": ceiling_risk,
    "reasoning": reasoning,
}

print(json.dumps(result, indent=2, ensure_ascii=False))
PYEOF
