#!/usr/bin/env bash
# quick-battle.sh — One-shot scaffolding from inline idea file paths.
#
# Lower-friction alternative to init-battle.sh. Instead of scaffolding stub
# files and asking the user to fill them in, this takes 2 or more idea files
# that already exist and produces a ready-to-run battle directory.
#
# Usage:
#   quick-battle.sh <idea1.md> <idea2.md> [<idea3.md> ...] \
#                   [--context <ctx.md>] \
#                   [--name "Battle name"] \
#                   [--rubric <name>] \
#                   [--out <dir>]
#
# Behavior:
#   - Accepts any N ≥ 2 idea files. The bracket is single-elimination; for
#     non-powers-of-2 (N = 3, 5, 6, 7, 9, ...), byes are auto-distributed to
#     the first contestants in input order. advance.sh handles the rest.
#   - Cost grows with N: each match spawns 2 defenders + 1 judge subagent,
#     and the bracket runs N - 1 matches total. We print a warning at N > 16
#     and abort at N > 32.
#   - Extracts each contestant's display name from the file's first H1
#     ("# Title" → "Title"), falling back to the basename if there is none
#   - Default output dir: ~/Documents/battles/<slug>-<YYYY-MM-DD-HHMMSS>/
#     (override with --out)
#   - Copies idea files into <dir>/ideas/ preserving filenames
#   - Copies context file into <dir>/context/ if provided; otherwise writes
#     a minimal stub that tells the judge there is no shared context
#   - Generates battle.yaml with real contestant names and a bracket
#   - Prints the battle directory path on the LAST line of stdout (other
#     diagnostic output goes to stderr) so callers can capture it:
#       BATTLE_DIR=$(quick-battle.sh foo.md bar.md | tail -1)

set -euo pipefail

# --- Parse args -------------------------------------------------------------

ideas=()
context=""
name=""
rubric="balanced"
out=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --context) context="$2"; shift 2 ;;
    --name)    name="$2";    shift 2 ;;
    --rubric)  rubric="$2";  shift 2 ;;
    --out)     out="$2";     shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0" >&2
      exit 0
      ;;
    --*) echo "ERROR: unknown flag: $1" >&2; exit 1 ;;
    *)   ideas+=("$1");      shift ;;
  esac
done

n="${#ideas[@]}"
if [[ "$n" -lt 2 ]]; then
  echo "ERROR: need at least 2 idea files, got $n" >&2
  echo "Usage: quick-battle.sh <idea1.md> <idea2.md> [<idea3.md> ...]" >&2
  exit 1
fi
if [[ "$n" -gt 32 ]]; then
  echo "ERROR: refusing to scaffold a battle with $n contestants (max 32)." >&2
  echo "  A battle with N contestants runs N-1 matches, each spawning 3" >&2
  echo "  Claude subagents (2 defenders + 1 judge). Cull your shortlist first." >&2
  exit 1
fi
if [[ "$n" -gt 16 ]]; then
  matches_total=$((n - 1))
  subagents_total=$((3 * matches_total))
  echo "WARNING: $n contestants = $matches_total matches = ~$subagents_total Claude subagents." >&2
  echo "  This is a large run. Consider culling your shortlist to ≤ 8 first." >&2
fi

for f in "${ideas[@]}"; do
  if [[ ! -r "$f" ]]; then
    echo "ERROR: idea file not readable: $f" >&2
    exit 1
  fi
done

if [[ -n "$context" && ! -r "$context" ]]; then
  echo "ERROR: context file not readable: $context" >&2
  exit 1
fi

# --- Resolve paths to absolute ---------------------------------------------

abspath() { python3 -c "import os,sys; print(os.path.abspath(sys.argv[1]))" "$1"; }

idea_abs=()
for f in "${ideas[@]}"; do
  idea_abs+=("$(abspath "$f")")
done

context_abs=""
if [[ -n "$context" ]]; then
  context_abs="$(abspath "$context")"
fi

# --- Derive contestant names from file H1 headers --------------------------

extract_title() {
  local file="$1"
  local fallback="$2"
  python3 - "$file" "$fallback" <<'PYEOF'
import re, sys
path, fallback = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            m = re.match(r"^#\s+(.+?)\s*$", line)
            if m:
                # Strip common decorators ("Option 1 — ", "Idea: ", etc.)
                title = m.group(1)
                # Trim emojis at the start
                title = re.sub(r"^[^\w(]*\s*", "", title)
                title = title.strip()
                if title:
                    print(title)
                    sys.exit(0)
except OSError:
    pass
print(fallback)
PYEOF
}

names=()
for i in "${!idea_abs[@]}"; do
  f="${idea_abs[$i]}"
  base="$(basename "$f" .md)"
  names+=("$(extract_title "$f" "$base")")
done

# --- Decide default battle name + output dir -------------------------------

if [[ -z "$name" ]]; then
  if [[ "$n" -eq 2 ]]; then
    name="${names[0]} vs ${names[1]}"
  else
    name="Decision battle ($n options)"
  fi
fi

slugify() {
  python3 -c "
import re,sys
s = sys.argv[1].lower()
s = re.sub(r'[^a-z0-9]+', '-', s).strip('-')
print(s[:60] or 'battle')
" "$1"
}
slug="$(slugify "$name")"
ts="$(date +%Y-%m-%d-%H%M%S)"

if [[ -z "$out" ]]; then
  out="$HOME/Documents/battles/${slug}-${ts}"
fi

if [[ -e "$out" ]]; then
  echo "ERROR: output dir already exists: $out" >&2
  echo "Pass --out <dir> with a new path." >&2
  exit 1
fi

# --- Scaffold the battle dir -----------------------------------------------

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rubric_path="$skill_dir/rubrics/${rubric}.yaml"
if [[ ! -r "$rubric_path" ]]; then
  echo "ERROR: rubric not found: $rubric_path" >&2
  exit 1
fi

mkdir -p "$out/ideas" "$out/context" "$out/output"

# Copy idea files in. Keep stable filenames idea-N.md so battle.yaml refs match.
specs=()
for i in "${!idea_abs[@]}"; do
  idx=$((i + 1))
  dest="$out/ideas/idea-${idx}.md"
  cp "${idea_abs[$i]}" "$dest"
  specs+=("ideas/idea-${idx}.md")
done

# Context: copy provided file, or write a minimal "no shared context" stub.
if [[ -n "$context_abs" ]]; then
  cp "$context_abs" "$out/context/shared-context.md"
else
  cat > "$out/context/shared-context.md" <<EOF
# Shared context for judges

(No shared context was provided for this battle.)

The judge should treat every claim defenders surface as unverified by default
and use WebSearch (budget: 3 queries per match) to verify the most
grade-determining interpretive claims. Claims that cannot be verified must
be downgraded per the v0.4 mandatory-downgrade rule.
EOF
fi

# Generate battle.yaml.
yaml_escape() { python3 -c "
import json,sys
print(json.dumps(sys.argv[1], ensure_ascii=False))
" "$1"; }

contestants_yaml=""
for i in "${!names[@]}"; do
  idx=$((i + 1))
  contestants_yaml+="  - id: \"$idx\"
    name: $(yaml_escape "${names[$i]}")
    spec: \"${specs[$i]}\"
"
done

# The bracket is built dynamically by advance.sh from the contestant list:
# single-elimination, with byes auto-distributed to the first contestants in
# input order if N is not a power of 2. Users who want explicit round-1
# pairings can hand-edit battle.yaml to add a `bracket: round-1:` block.

cat > "$out/battle.yaml" <<EOF
name: $(yaml_escape "$name")
date: "$(date +%Y-%m-%d)"

contestants:
${contestants_yaml}
rubric: "$rubric_path"
context: "context/shared-context.md"

format: "bracket"
# bracket: round-1 pairings are auto-generated by advance.sh from contestant
# input order. Override here only if you want explicit seeding.
# Example for 4 contestants:
#   bracket:
#     round-1:
#       - ["1", "3"]
#       - ["2", "4"]
EOF

# --- Report -----------------------------------------------------------------

{
  echo "Scaffolded battle: $name"
  echo "  Output dir:  $out"
  echo "  Contestants ($n):"
  for i in "${!names[@]}"; do
    idx=$((i + 1))
    echo "    $idx. ${names[$i]}  ←  ${idea_abs[$i]}"
  done
  if [[ -n "$context_abs" ]]; then
    echo "  Context:     $context_abs"
  else
    echo "  Context:     (none provided — judge will lean on WebSearch)"
  fi
  echo
  echo "Ready to run. Next step: invoke /decision-battle-royale run $out"
} >&2

# Print the battle dir as the LAST stdout line so callers can capture it.
echo "$out"
