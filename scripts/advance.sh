#!/usr/bin/env bash
# advance.sh — After Round-N is complete, determine winners and write next-round config.
#
# Usage:
#   advance.sh <battle-dir>
#
# Reads:
#   <battle-dir>/battle.yaml              (semifinal pairings + final spec)
#   <battle-dir>/output/round-N/match-X/verdict.json  for each match in round N
#
# Writes:
#   <battle-dir>/output/round-{N+1}/bracket.json      next round's pairings (resolved)
#   <battle-dir>/output/state.json                    overall battle state
#
# Behavior:
#   - 4-contestant bracket: round 1 = 2 semifinal matches, round 2 = final.
#   - 2-contestant bracket: round 1 = the only match (final).
#   - Idempotent: safe to re-run.

set -euo pipefail

battle_dir="${1:?Usage: advance.sh <battle-dir>}"
[[ -d "$battle_dir" ]] || { echo "ERROR: battle dir not found: $battle_dir" >&2; exit 1; }
[[ -f "$battle_dir/battle.yaml" ]] || { echo "ERROR: battle.yaml not found" >&2; exit 1; }

python3 - "$battle_dir" <<'PYEOF'
import json, re, sys
from pathlib import Path

battle_dir = Path(sys.argv[1])
battle_yaml = battle_dir / "battle.yaml"
output_dir = battle_dir / "output"
output_dir.mkdir(exist_ok=True)

# --- Lightweight YAML parser for the subset we use ---
def parse_battle_yaml(path):
    """Parse the subset of YAML used by battle.yaml. Returns dict."""
    text = path.read_text(encoding="utf-8")
    result = {"contestants": [], "rounds": []}

    # Top-level scalar fields
    for key in ("name", "date", "rubric", "context", "format"):
        m = re.search(rf"^{key}:\s*[\"']?(.+?)[\"']?\s*$", text, re.MULTILINE)
        if m:
            result[key] = m.group(1).strip()

    # contestants: list of {id, name, spec}
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
                    result["contestants"].append(current)
                current = {"id": m_id.group(1)}
                continue
            for f in ("name", "spec"):
                m = re.match(rf"\s+{f}:\s*[\"']?(.+?)[\"']?\s*$", line)
                if m and current is not None:
                    current[f] = m.group(1).strip()
    if current:
        result["contestants"].append(current)

    # bracket / rounds — supports two shapes:
    #   bracket:
    #     semifinals:
    #       - ["1", "3"]
    #       - ["2", "4"]
    # OR
    #   bracket:
    #     rounds:
    #       - name: "Semifinal"
    #         matches:
    #           - { id: "A", contestants: ["1", "3"] }
    # We'll just look for the simpler `semifinals` format here.
    semifinals = []
    in_semifinals = False
    for line in text.splitlines():
        if re.match(r"\s+semifinals:\s*$", line):
            in_semifinals = True
            continue
        if in_semifinals:
            m = re.match(r"\s+-\s*\[\s*[\"']([^\"']+)[\"']\s*,\s*[\"']([^\"']+)[\"']\s*\]", line)
            if m:
                semifinals.append([m.group(1), m.group(2)])
            elif re.match(r"^\S", line) or re.match(r"^\s+[a-z_]+:", line) and "semifinals" not in line:
                in_semifinals = False
    result["semifinals"] = semifinals
    return result


config = parse_battle_yaml(battle_yaml)
contestants = {c["id"]: c for c in config["contestants"]}
n_contestants = len(contestants)

if n_contestants not in (2, 4):
    sys.stderr.write(f"ERROR: only 2 or 4 contestants supported in v0.1, got {n_contestants}\n")
    sys.exit(2)

# --- State: load verdict files for each round ---
def read_verdict(round_n, match_id):
    path = output_dir / f"round-{round_n}" / f"match-{match_id}" / "verdict.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))

def winner_contestant_id(round_n, match_id, pair):
    """Returns the contestant id (e.g. '1' or '3') that won this match."""
    v = read_verdict(round_n, match_id)
    if v is None:
        return None
    # In our convention, contestants in the pair are A and B in order.
    return pair[0] if v["winner"] == "A" else pair[1]

# --- Build state ---
state = {
    "name": config.get("name", "Battle"),
    "n_contestants": n_contestants,
    "contestants": list(contestants.keys()),
    "rounds": [],
    "current_round": None,
    "complete": False,
    "champion": None,
}

if n_contestants == 2:
    # Single-match battle: round 1 IS the final.
    pair = list(contestants.keys())
    round1 = {
        "n": 1,
        "name": "Final",
        "matches": [{"id": "F", "contestants": pair, "winner": None}],
    }
    v1 = read_verdict(1, "F")
    if v1:
        round1["matches"][0]["winner"] = winner_contestant_id(1, "F", pair)
        state["champion"] = round1["matches"][0]["winner"]
        state["complete"] = True
    state["rounds"].append(round1)
    state["current_round"] = 1 if v1 is None else None

elif n_contestants == 4:
    # 4-contestant bracket: 2 semifinal matches + 1 final.
    semis = config.get("semifinals", [])
    if len(semis) != 2:
        sys.stderr.write(f"ERROR: 4-contestant bracket requires 2 semifinals, got {len(semis)}\n")
        sys.exit(2)
    semi_a, semi_b = semis[0], semis[1]

    round1 = {
        "n": 1,
        "name": "Semifinal",
        "matches": [
            {"id": "A", "contestants": semi_a, "winner": None},
            {"id": "B", "contestants": semi_b, "winner": None},
        ],
    }
    wa = winner_contestant_id(1, "A", semi_a)
    wb = winner_contestant_id(1, "B", semi_b)
    if wa: round1["matches"][0]["winner"] = wa
    if wb: round1["matches"][1]["winner"] = wb
    state["rounds"].append(round1)

    if wa and wb:
        round2 = {
            "n": 2,
            "name": "Final",
            "matches": [{"id": "F", "contestants": [wa, wb], "winner": None}],
        }
        v2 = read_verdict(2, "F")
        if v2:
            round2["matches"][0]["winner"] = winner_contestant_id(2, "F", [wa, wb])
            state["champion"] = round2["matches"][0]["winner"]
            state["complete"] = True
        state["rounds"].append(round2)
        state["current_round"] = 2 if not state["complete"] else None
    else:
        state["current_round"] = 1

# Write state and next-round bracket file
state_path = output_dir / "state.json"
state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False))

if state["current_round"]:
    cr = state["current_round"]
    round_dir = output_dir / f"round-{cr}"
    round_dir.mkdir(exist_ok=True)
    bracket = next(r for r in state["rounds"] if r["n"] == cr)
    (round_dir / "bracket.json").write_text(json.dumps(bracket, indent=2, ensure_ascii=False))
    print(f"Current round: {cr} ({bracket['name']})")
    for m in bracket["matches"]:
        cs = m["contestants"]
        a_name = contestants[cs[0]].get("name", cs[0])
        b_name = contestants[cs[1]].get("name", cs[1])
        status = "complete" if m.get("winner") else "pending"
        print(f"  match {m['id']}: {a_name}  vs  {b_name}  [{status}]")
elif state["complete"]:
    champ_name = contestants[state["champion"]].get("name", state["champion"])
    print(f"BATTLE COMPLETE — Champion: {champ_name} (id={state['champion']})")

print(f"\nState written to: {state_path}")
PYEOF
