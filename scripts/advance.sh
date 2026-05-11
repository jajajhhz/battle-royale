#!/usr/bin/env bash
# advance.sh — After a round is complete, determine winners and write
#              next-round bracket config.
#
# Usage:
#   advance.sh <battle-dir>
#
# Reads:
#   <battle-dir>/battle.yaml                              — contestants + optional bracket
#   <battle-dir>/output/round-N/match-X/verdict.json      — per-match outcomes
#
# Writes:
#   <battle-dir>/output/round-{N+1}/bracket.json          — next round's pairings (resolved)
#   <battle-dir>/output/state.json                        — overall battle state
#
# Format:
#   Single-elimination bracket over N ≥ 2 contestants. For non-powers-of-2,
#   byes are distributed to the first contestants in input order in round 1
#   (one round of byes only — every contestant plays at least once unless
#   the user explicitly seeds them with a bye via `bracket.round-1`).
#
#   Round naming (by the number of contestants entering the round):
#     2  → "Final"
#     4  → "Semifinal"
#     8  → "Quarterfinal"
#     16 → "Round of 16"
#     N  → "Round of N"   (for other values)
#
# Behavior:
#   - Idempotent: safe to re-run after partial completion.
#   - Backward-compatible with v0.5 battle.yaml that uses `bracket.semifinals`
#     for 4-contestant battles — this is now treated as an explicit round-1
#     override.

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


# --- Lightweight YAML parser for the subset we use --------------------------
def parse_battle_yaml(path):
    """Parse the subset of YAML used by battle.yaml. Returns dict with:
       - name, date, rubric, context, format (scalars)
       - contestants: [{id, name, spec}]
       - explicit_round_1: optional [[a_id, b_id], ...] from bracket.round-1
         or legacy bracket.semifinals (both are interpreted as round-1 pairings)
    """
    text = path.read_text(encoding="utf-8")
    result = {"contestants": []}

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

    # Optional explicit round-1 pairings. Two accepted keys:
    #   bracket.round-1:        (preferred — works for any N)
    #   bracket.semifinals:     (legacy v0.1-v0.5 — only meaningful when N=4)
    explicit = []
    for key in ("round-1", "semifinals"):
        in_section = False
        for line in text.splitlines():
            if re.match(rf"\s+{key}:\s*$", line):
                in_section = True
                continue
            if in_section:
                m = re.match(r"\s+-\s*\[\s*[\"']([^\"']+)[\"']\s*,\s*[\"']([^\"']+)[\"']\s*\]", line)
                if m:
                    explicit.append([m.group(1), m.group(2)])
                elif re.match(r"^\S", line) or (re.match(r"^\s+[a-z_-]+:", line) and key not in line):
                    in_section = False
        if explicit:
            break  # use the first key that yielded pairings
    result["explicit_round_1"] = explicit
    return result


# --- Bracket builder --------------------------------------------------------
def round_name(entry_count):
    """Name a round by how many contestants enter it."""
    if entry_count == 2:
        return "Final"
    if entry_count == 4:
        return "Semifinal"
    if entry_count == 8:
        return "Quarterfinal"
    return f"Round of {entry_count}"


def build_round_1(contestant_ids, explicit_round_1=None):
    """Returns (matches, byes) for round 1.

    matches: [[a_id, b_id], ...]
    byes:    [contestant_id, ...] (these contestants advance to round 2 without playing round 1)
    """
    n = len(contestant_ids)
    if explicit_round_1:
        # User specified explicit round-1 pairings. Everyone not paired is a bye.
        paired = {c for pair in explicit_round_1 for c in pair}
        byes = [c for c in contestant_ids if c not in paired]
        return list(explicit_round_1), byes

    # Auto-pair: byes to the first `next_pow2(n) - n` contestants in input order.
    if n < 2:
        raise ValueError(f"need at least 2 contestants, got {n}")
    next_pow2 = 1
    while next_pow2 < n:
        next_pow2 *= 2
    byes_count = next_pow2 - n
    byes = contestant_ids[:byes_count]
    play = contestant_ids[byes_count:]
    matches = [[play[i], play[i + 1]] for i in range(0, len(play), 2)]
    return matches, byes


def label_matches(matches, round_n):
    """Assign letter IDs to matches (A, B, C, ...). For more than 26 matches,
    we fall back to AA, AB, ... — unlikely in practice (would need N > 52)."""
    labeled = []
    for i, pair in enumerate(matches):
        if i < 26:
            mid = chr(ord("A") + i)
        else:
            mid = "A" + chr(ord("A") + (i - 26))
        labeled.append({"id": mid, "contestants": pair, "winner": None})
    # When this is the final (1 match in last round), use "F" by convention
    # for back-compat with existing 2- and 4-contestant battles.
    if len(labeled) == 1 and round_n is not None:
        # Caller decides whether to rename to "F" based on whether this is the
        # last round. We do it here only if this is a single-match final.
        pass
    return labeled


# --- Verdict reading --------------------------------------------------------
def read_verdict(round_n, match_id):
    path = output_dir / f"round-{round_n}" / f"match-{match_id}" / "verdict.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def winner_id(round_n, match_id, pair):
    v = read_verdict(round_n, match_id)
    if v is None:
        return None
    return pair[0] if v["winner"] == "A" else pair[1]


# --- Build the full bracket dynamically -------------------------------------
config = parse_battle_yaml(battle_yaml)
contestants = {c["id"]: c for c in config["contestants"]}
contestant_order = [c["id"] for c in config["contestants"]]
n_contestants = len(contestant_order)

if n_contestants < 2:
    sys.stderr.write(f"ERROR: need at least 2 contestants, got {n_contestants}\n")
    sys.exit(2)

# Build round 1 (the only round where contestant identities are known upfront).
round_1_matches, round_1_byes = build_round_1(contestant_order, config.get("explicit_round_1"))

# Walk rounds, resolving winners as we have them.
state_rounds = []
current_round_n = None
champion = None

# Round 1
r1_entry_count = n_contestants
r1_labeled = label_matches(round_1_matches, 1)
# Special case: if round 1 IS the final (n=2), label as F for back-compat
if len(r1_labeled) == 1 and not round_1_byes:
    r1_labeled[0]["id"] = "F"
for m in r1_labeled:
    m["winner"] = winner_id(1, m["id"], m["contestants"])
state_rounds.append({
    "n": 1,
    "name": round_name(r1_entry_count),
    "matches": r1_labeled,
    "byes": list(round_1_byes),
})

# Subsequent rounds: built from previous round's winners + byes propagated forward.
prev_winners = [m["winner"] for m in r1_labeled]
prev_byes = list(round_1_byes)

round_n = 2
while True:
    # Contestants entering this round are: byes from the prior round + winners from the prior round.
    entrants = []
    for b in prev_byes:
        entrants.append(b)
    for w in prev_winners:
        if w is not None:
            entrants.append(w)
        else:
            # We don't know all winners yet; this round can't be planned in full.
            entrants.append(None)

    # If we don't know all entrants yet, stop here — the round isn't ready.
    if any(e is None for e in entrants):
        break

    # If only one contestant remains, they're the champion.
    if len(entrants) == 1:
        champion = entrants[0]
        break

    # Otherwise, pair up entrants for this round (no further byes — every round
    # after round 1 has a power-of-2 entry count by construction).
    matches_this_round = [[entrants[i], entrants[i + 1]] for i in range(0, len(entrants), 2)]
    labeled = label_matches(matches_this_round, round_n)
    # Single-match final → use "F" id
    if len(labeled) == 1:
        labeled[0]["id"] = "F"
    for m in labeled:
        m["winner"] = winner_id(round_n, m["id"], m["contestants"])

    state_rounds.append({
        "n": round_n,
        "name": round_name(len(entrants)),
        "matches": labeled,
        "byes": [],
    })

    prev_winners = [m["winner"] for m in labeled]
    prev_byes = []
    round_n += 1

# Determine current round (first round with any pending match)
for r in state_rounds:
    if any(m["winner"] is None for m in r["matches"]):
        current_round_n = r["n"]
        break

complete = champion is not None and current_round_n is None

# --- Write state and (if applicable) the current round's bracket file -------
state = {
    "name": config.get("name", "Battle"),
    "n_contestants": n_contestants,
    "contestants": contestant_order,
    "rounds": state_rounds,
    "current_round": current_round_n,
    "complete": complete,
    "champion": champion,
}

state_path = output_dir / "state.json"
state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False))

if current_round_n is not None:
    cr = current_round_n
    round_dir = output_dir / f"round-{cr}"
    round_dir.mkdir(exist_ok=True)
    bracket = next(r for r in state_rounds if r["n"] == cr)
    (round_dir / "bracket.json").write_text(json.dumps(bracket, indent=2, ensure_ascii=False))
    print(f"Current round: {cr} ({bracket['name']})")
    if bracket["byes"]:
        bye_names = ", ".join(contestants[b].get("name", b) for b in bracket["byes"])
        print(f"  byes: {bye_names}")
    for m in bracket["matches"]:
        cs = m["contestants"]
        a_name = contestants[cs[0]].get("name", cs[0])
        b_name = contestants[cs[1]].get("name", cs[1])
        status = "complete" if m.get("winner") else "pending"
        print(f"  match {m['id']}: {a_name}  vs  {b_name}  [{status}]")
elif complete:
    champ_name = contestants[champion].get("name", champion)
    print(f"BATTLE COMPLETE — Champion: {champ_name} (id={champion})")

print(f"\nState written to: {state_path}")
PYEOF
