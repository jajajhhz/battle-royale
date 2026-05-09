#!/usr/bin/env bash
# summary.sh — Generate the final markdown report for a completed battle.
#
# Usage:
#   summary.sh <battle-dir>
#
# Reads:
#   <battle-dir>/output/state.json
#   <battle-dir>/output/round-N/match-X/verdict.json
#
# Writes:
#   <battle-dir>/output/final-report.md

set -euo pipefail

battle_dir="${1:?Usage: summary.sh <battle-dir>}"
[[ -d "$battle_dir/output" ]] || { echo "ERROR: no output directory in $battle_dir" >&2; exit 1; }

python3 - "$battle_dir" <<'PYEOF'
import json, sys
from pathlib import Path

battle_dir = Path(sys.argv[1])
output_dir = battle_dir / "output"
state_path = output_dir / "state.json"
if not state_path.exists():
    sys.stderr.write("ERROR: state.json not found. Run advance.sh first.\n")
    sys.exit(1)

state = json.loads(state_path.read_text(encoding="utf-8"))

# Load contestant names from battle.yaml (lightweight parse)
import re
contestants = {}
with open(battle_dir / "battle.yaml", encoding="utf-8") as f:
    text = f.read()
in_contestants = False
current = None
for line in text.splitlines():
    if re.match(r"^contestants:\s*$", line):
        in_contestants = True
        continue
    if in_contestants and re.match(r"^[a-z_]+:\s*$", line) and not line.startswith(" "):
        in_contestants = False
    if in_contestants:
        m_id = re.match(r"\s*-\s*id:\s*[\"']?([^\"'\s]+)[\"']?", line)
        if m_id:
            if current:
                contestants[current["id"]] = current
            current = {"id": m_id.group(1)}
            continue
        for f in ("name",):
            m = re.match(rf"\s+{f}:\s*[\"']?(.+?)[\"']?\s*$", line)
            if m and current is not None:
                current[f] = m.group(1).strip()
if current:
    contestants[current["id"]] = current

def cname(cid):
    return contestants.get(cid, {}).get("name", cid)

# Build cumulative scoreboard
cumulative = {cid: {"name": cname(cid), "rounds": [], "total": 0.0} for cid in state["contestants"]}

for round_info in state["rounds"]:
    n = round_info["n"]
    for match in round_info["matches"]:
        cs = match["contestants"]
        verdict_path = output_dir / f"round-{n}" / f"match-{match['id']}" / "verdict.json"
        if not verdict_path.exists():
            continue
        v = json.loads(verdict_path.read_text(encoding="utf-8"))
        for letter, cid in zip(["A", "B"], cs):
            score = v[f"weighted_total_{letter.lower()}"]
            cumulative[cid]["rounds"].append({
                "round": round_info["name"],
                "match": match["id"],
                "score": score,
                "winner": cid == match.get("winner"),
            })
            cumulative[cid]["total"] += score

# Sort cumulative by total desc
sorted_cumulative = sorted(cumulative.values(), key=lambda x: -x["total"])

# Render report
lines = []
lines.append(f"# Battle Royale — Final Report")
lines.append("")
lines.append(f"**Battle:** {state.get('name', 'Unnamed Battle')}")
lines.append(f"**Contestants:** {state['n_contestants']}")
lines.append(f"**Status:** {'Complete' if state['complete'] else 'In progress'}")
lines.append("")

if state["complete"] and state["champion"]:
    champ = cname(state["champion"])
    lines.append(f"## 🏆 Champion: {champ}")
    lines.append("")

# Cumulative scoreboard
lines.append("## Cumulative scoreboard")
lines.append("")
lines.append("| Idea | Total points | Rounds played | Status |")
lines.append("|---|---|---|---|")
for entry in sorted_cumulative:
    total = round(entry["total"], 1)
    rounds_str = ", ".join(f"{r['round']} ({r['score']:.1f})" for r in entry["rounds"]) or "—"
    if state["champion"] == next(c for c, e in cumulative.items() if e is entry):
        status = "🏆 Champion"
    elif entry["rounds"] and entry["rounds"][-1].get("winner"):
        status = "Advanced"
    elif entry["rounds"]:
        status = "Eliminated"
    else:
        status = "—"
    lines.append(f"| {entry['name']} | **{total}** | {rounds_str} | {status} |")
lines.append("")

# Per-round detail
for round_info in state["rounds"]:
    n = round_info["n"]
    lines.append(f"## Round {n}: {round_info['name']}")
    lines.append("")
    for match in round_info["matches"]:
        cs = match["contestants"]
        verdict_path = output_dir / f"round-{n}" / f"match-{match['id']}" / "verdict.json"
        a_name = cname(cs[0])
        b_name = cname(cs[1])
        if not verdict_path.exists():
            lines.append(f"### Match {match['id']}: {a_name} vs {b_name}")
            lines.append("*(pending)*")
            lines.append("")
            continue
        v = json.loads(verdict_path.read_text(encoding="utf-8"))
        winner_name = a_name if v["winner"] == "A" else b_name
        lines.append(f"### Match {match['id']}: {a_name} vs {b_name}")
        lines.append("")
        lines.append(f"**Winner:** {winner_name}")
        lines.append(f"**Score:** {v['weighted_total_a']} vs {v['weighted_total_b']}")
        lines.append("")
        lines.append("| Criterion | Wt | " + a_name + " | " + b_name + " |")
        lines.append("|---|---|---|---|")
        for crit_id, sc in v["scores"].items():
            lines.append(f"| {sc['name']} | {sc['weight']} | {sc['a']}/10 | {sc['b']}/10 |")
        lines.append(f"| **Weighted total** | | **{v['weighted_total_a']}** | **{v['weighted_total_b']}** |")
        lines.append("")
        if v.get("deciding_factor"):
            lines.append("**Deciding factor:**")
            lines.append("")
            lines.append("> " + v["deciding_factor"].replace("\n", "\n> "))
            lines.append("")
        if v.get("ceiling_risk"):
            lines.append("**Ceiling × risk:**")
            lines.append("")
            lines.append("> " + v["ceiling_risk"].replace("\n", "\n> "))
            lines.append("")

# Cross-judge meta-analysis if multiple matches
if sum(len(r["matches"]) for r in state["rounds"]) > 1:
    lines.append("## Meta-analysis")
    lines.append("")
    deciding_factors = []
    for round_info in state["rounds"]:
        n = round_info["n"]
        for match in round_info["matches"]:
            verdict_path = output_dir / f"round-{n}" / f"match-{match['id']}" / "verdict.json"
            if verdict_path.exists():
                v = json.loads(verdict_path.read_text(encoding="utf-8"))
                if v.get("deciding_factor"):
                    deciding_factors.append({
                        "round": round_info["name"],
                        "match": match["id"],
                        "factor": v["deciding_factor"][:200] + ("..." if len(v["deciding_factor"]) > 200 else ""),
                    })
    if deciding_factors:
        lines.append("### Deciding factors across matches")
        lines.append("")
        for df in deciding_factors:
            lines.append(f"- **{df['round']} match {df['match']}**: {df['factor']}")
        lines.append("")

report_path = output_dir / "final-report.md"
report_path.write_text("\n".join(lines), encoding="utf-8")
print(f"Final report written to: {report_path}")
PYEOF
