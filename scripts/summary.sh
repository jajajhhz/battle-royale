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
#
# v0.2: renders qualitative grade tables (Strong/Neutral/Weak) instead of numeric scores.

set -euo pipefail

battle_dir="${1:?Usage: summary.sh <battle-dir>}"
[[ -d "$battle_dir/output" ]] || { echo "ERROR: no output directory in $battle_dir" >&2; exit 1; }

python3 - "$battle_dir" <<'PYEOF'
import json, re, sys
from pathlib import Path

battle_dir = Path(sys.argv[1])
output_dir = battle_dir / "output"
state_path = output_dir / "state.json"
if not state_path.exists():
    sys.stderr.write("ERROR: state.json not found. Run advance.sh first.\n")
    sys.exit(1)

state = json.loads(state_path.read_text(encoding="utf-8"))

# Load contestant names from battle.yaml
contestants = {}
text = (battle_dir / "battle.yaml").read_text(encoding="utf-8")
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
        m_name = re.match(r"\s+name:\s*[\"']?(.+?)[\"']?\s*$", line)
        if m_name and current is not None:
            current["name"] = m_name.group(1).strip()
if current:
    contestants[current["id"]] = current


def cname(cid):
    return contestants.get(cid, {}).get("name", cid)


# Cumulative differential per contestant
cumulative = {
    cid: {"name": cname(cid), "rounds": [], "total_diff": 0.0}
    for cid in state["contestants"]
}

for round_info in state["rounds"]:
    n = round_info["n"]
    for match in round_info["matches"]:
        cs = match["contestants"]
        verdict_path = output_dir / f"round-{n}" / f"match-{match['id']}" / "verdict.json"
        if not verdict_path.exists():
            continue
        v = json.loads(verdict_path.read_text(encoding="utf-8"))
        for letter, cid in zip(["a", "b"], cs):
            diff = v[f"differential_{letter}"]
            cumulative[cid]["rounds"].append(
                {
                    "round": round_info["name"],
                    "match": match["id"],
                    "diff": diff,
                    "winner": cid == match.get("winner"),
                }
            )
            cumulative[cid]["total_diff"] += diff

sorted_cumulative = sorted(cumulative.values(), key=lambda x: -x["total_diff"])

# --- Render report ---
lines = []
lines.append("# Battle Royale — Final Report")
lines.append("")
lines.append(f"**Battle:** {state.get('name', 'Unnamed Battle')}")
lines.append(f"**Contestants:** {state['n_contestants']}")
lines.append(f"**Status:** {'Complete' if state['complete'] else 'In progress'}")
lines.append("")

if state["complete"] and state["champion"]:
    champ = cname(state["champion"])
    lines.append(f"## 🏆 Champion: {champ}")
    lines.append("")

# Cumulative scoreboard (differentials)
lines.append("## Cumulative scoreboard (grade differentials)")
lines.append("")
lines.append("Each match contributes a weighted grade differential per contestant.")
lines.append("Strong = +1×weight, Neutral = 0, Weak = −1×weight, summed per match.")
lines.append("")
lines.append("| Idea | Cumulative differential | Rounds played | Status |")
lines.append("|---|---|---|---|")
for entry in sorted_cumulative:
    total = round(entry["total_diff"], 2)
    rounds_str = (
        ", ".join(f"{r['round']} ({r['diff']:+.2f})" for r in entry["rounds"]) or "—"
    )
    cid = next(c for c, e in cumulative.items() if e is entry)
    if state["champion"] == cid:
        status = "🏆 Champion"
    elif entry["rounds"] and entry["rounds"][-1].get("winner"):
        status = "Advanced"
    elif entry["rounds"]:
        status = "Eliminated"
    else:
        status = "—"
    sign = "+" if total >= 0 else ""
    lines.append(
        f"| {entry['name']} | **{sign}{total}** | {rounds_str} | {status} |"
    )
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
        lines.append(
            f"**Differential:** A {v['differential_a']:+.2f}  vs  B {v['differential_b']:+.2f}"
        )
        if v.get("score_winner") == "TIE":
            lines.append(
                "*Note: differentials tied; verdict declared via tiebreaker (see deciding factor).*"
            )
        lines.append("")
        lines.append(f"| Criterion | Wt | {a_name} | {b_name} |")
        lines.append("|---|---|---|---|")
        for crit_id, g in v["grades"].items():
            a_cell = f"**{g['a_grade']}** — {g['a_proofs']}" if g["a_proofs"] else f"**{g['a_grade']}**"
            b_cell = f"**{g['b_grade']}** — {g['b_proofs']}" if g["b_proofs"] else f"**{g['b_grade']}**"
            lines.append(f"| {g['name']} | {g['weight']} | {a_cell} | {b_cell} |")
        lines.append(
            f"| **Differential** | | **{v['differential_a']:+.2f}** | **{v['differential_b']:+.2f}** |"
        )
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

# Cross-match meta-analysis if multiple matches
if sum(len(r["matches"]) for r in state["rounds"]) > 1:
    lines.append("## Meta-analysis")
    lines.append("")
    lines.append("### Deciding factors across matches")
    lines.append("")
    for round_info in state["rounds"]:
        n = round_info["n"]
        for match in round_info["matches"]:
            verdict_path = (
                output_dir / f"round-{n}" / f"match-{match['id']}" / "verdict.json"
            )
            if verdict_path.exists():
                v = json.loads(verdict_path.read_text(encoding="utf-8"))
                if v.get("deciding_factor"):
                    factor = v["deciding_factor"][:240] + (
                        "..." if len(v["deciding_factor"]) > 240 else ""
                    )
                    lines.append(
                        f"- **{round_info['name']} match {match['id']}**: {factor}"
                    )
    lines.append("")

report_path = output_dir / "final-report.md"
report_path.write_text("\n".join(lines), encoding="utf-8")
print(f"Final report written to: {report_path}")
PYEOF
