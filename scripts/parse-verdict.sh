#!/usr/bin/env bash
# parse-verdict.sh — Extract structured grades + proofs from a judge verdict.md
#
# Usage:
#   parse-verdict.sh <verdict.md> <rubric.yaml>
#
# Output: JSON with keys:
#   {
#     "verdict": "Idea A" | "Idea B",
#     "grades": {
#       "criterion_id": {
#         "name": "...",
#         "weight": float,
#         "a_grade": "Strong"|"Neutral"|"Weak",
#         "a_proofs": "...",
#         "b_grade": "Strong"|"Neutral"|"Weak",
#         "b_proofs": "..."
#       }
#     },
#     "differential_a": float,   # Σ (a_points × weight)
#     "differential_b": float,   # Σ (b_points × weight)
#     "winner": "A"|"B",
#     "score_winner": "A"|"B"|"TIE",
#     "deciding_factor": "...",
#     "ceiling_risk": "...",
#     "reasoning": "..."
#   }
#
# Exit codes:
#   0  parsed cleanly
#   2  format error (missing grades, malformed table)

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

# --- Parse rubric criteria ---
rubric_text = rubric_path.read_text(encoding="utf-8")
criteria = []
current = None
for line in rubric_text.splitlines():
    s = line.rstrip()
    m_id = re.match(r"\s*- id:\s*(\S+)", s)
    if m_id:
        if current and "name" in current and "weight" in current:
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
if current and "name" in current and "weight" in current:
    criteria.append(current)

if not criteria:
    sys.stderr.write("ERROR: no criteria parsed from rubric\n")
    sys.exit(2)

# --- Parse verdict ---
verdict_match = re.search(r"##\s*VERDICT:\s*Idea\s*([AB])\b", verdict_text, re.IGNORECASE)
if not verdict_match:
    sys.stderr.write("ERROR: no VERDICT line found\n")
    sys.exit(2)
winner_letter = verdict_match.group(1).upper()

# --- Parse grades table ---
# Row format:
#   | N. Criterion Name | weight | <Strong/Neutral/Weak> | "<A proofs>" | <grade> | "<B proofs>" |
# Be tolerant of bold markers (**Strong**), backticks, italics, etc.
GRADE_PATTERN = r"(?P<grade>Strong|Neutral|Weak)"
GRADE_POINTS = {"Strong": 1, "Neutral": 0, "Weak": -1}

grades = {}
for crit in criteria:
    name = crit["name"]
    # Match the row containing the criterion name. Allow flexible whitespace and decoration.
    # Capture: weight, A grade, A proofs, B grade, B proofs
    # Grade cell may include annotation after the grade word
    # (e.g. "Neutral (DOWNGRADED from Strong)" — v0.4 judges flag downgrades).
    # We capture the grade word at the start of the cell and ignore the rest until |.
    pattern = (
        r"\|\s*\d+\.\s*"
        + re.escape(name)
        + r"\s*\|\s*(?P<wt>[0-9.]+)\s*\|\s*\**\s*(?P<a_grade>Strong|Neutral|Weak)\b[^|]*\|"
        + r"\s*(?P<a_proofs>[^|]*?)\s*\|\s*\**\s*(?P<b_grade>Strong|Neutral|Weak)\b[^|]*\|"
        + r"\s*(?P<b_proofs>[^|]*?)\s*\|"
    )
    m = re.search(pattern, verdict_text, re.IGNORECASE | re.DOTALL)
    if not m:
        sys.stderr.write(f"ERROR: could not parse grade row for criterion: {name}\n")
        sys.exit(2)

    a_grade = m.group("a_grade").capitalize()
    b_grade = m.group("b_grade").capitalize()
    weight_in_table = float(m.group("wt"))
    if abs(weight_in_table - crit["weight"]) > 0.01:
        sys.stderr.write(
            f"WARN: weight mismatch for {name}: rubric={crit['weight']} table={weight_in_table}\n"
        )

    grades[crit["id"]] = {
        "name": name,
        "weight": crit["weight"],
        "a_grade": a_grade,
        "a_proofs": m.group("a_proofs").strip(),
        "b_grade": b_grade,
        "b_proofs": m.group("b_proofs").strip(),
    }

# --- Compute differentials ---
diff_a = round(sum(GRADE_POINTS[g["a_grade"]] * g["weight"] for g in grades.values()), 2)
diff_b = round(sum(GRADE_POINTS[g["b_grade"]] * g["weight"] for g in grades.values()), 2)

if diff_a > diff_b:
    score_winner = "A"
elif diff_b > diff_a:
    score_winner = "B"
else:
    score_winner = "TIE"

if score_winner != "TIE" and score_winner != winner_letter:
    sys.stderr.write(
        f"WARN: stated VERDICT ({winner_letter}) disagrees with grade-differential winner ({score_winner})\n"
    )

# --- Extract narrative sections ---
def extract_section(text, header):
    pattern = rf"##\s*{re.escape(header)}\s*\n+(.*?)(?=\n##\s|\Z)"
    m = re.search(pattern, text, re.DOTALL | re.IGNORECASE)
    return m.group(1).strip() if m else ""

deciding_factor = extract_section(verdict_text, "THE DECIDING FACTOR")
ceiling_risk = (
    extract_section(verdict_text, "CEILING × RISK ASSESSMENT")
    or extract_section(verdict_text, "CEILING x RISK ASSESSMENT")
)
reasoning = extract_section(verdict_text, "REASONING")
searches_performed_text = extract_section(verdict_text, "SEARCHES PERFORMED")

# Parse the SEARCHES PERFORMED block into structured queries.
# Expected format (per v0.4 judge prompt):
#   "Query: <q> → Finding: <f>"  (one per line, possibly wrapped)
# We're forgiving: any line matching `Query:` is captured, and `Finding:`
# extends it. Empty results are recorded with a synthetic note.
def parse_searches(block_text):
    if not block_text:
        return []
    queries = []
    current = None
    for line in block_text.splitlines():
        s = line.strip()
        m = re.match(r"^[*\-]?\s*Query:\s*(.+?)(?:\s*[→\->]+\s*Finding:\s*(.+))?$", s, re.IGNORECASE)
        if m:
            if current:
                queries.append(current)
            current = {
                "query": m.group(1).strip().rstrip('"\''),
                "finding": (m.group(2) or "").strip(),
            }
            continue
        # Continuation line — append to the last query's finding.
        if current and s:
            sep = " " if current["finding"] else ""
            current["finding"] += sep + s
    if current:
        queries.append(current)
    return queries

searches_performed = parse_searches(searches_performed_text)

# Detect "judge said no searches" patterns even when SEARCHES PERFORMED is
# present but says "None" / "0 searches" — useful for audit scoring.
no_search_marker = bool(re.search(
    r"\b(None|0\s*(?:of\s*3|queries|searches))\b",
    (searches_performed_text or "").split("\n", 1)[0] if searches_performed_text else "",
    re.IGNORECASE,
))

result = {
    "verdict": f"Idea {winner_letter}",
    "winner": winner_letter,
    "grades": grades,
    "differential_a": diff_a,
    "differential_b": diff_b,
    "score_winner": score_winner,
    "deciding_factor": deciding_factor,
    "ceiling_risk": ceiling_risk,
    "reasoning": reasoning,
    "searches_performed": searches_performed,
    "searches_performed_raw": searches_performed_text,
    "searches_count": len(searches_performed),
    "no_search_marker": no_search_marker,
}

print(json.dumps(result, indent=2, ensure_ascii=False))
PYEOF
