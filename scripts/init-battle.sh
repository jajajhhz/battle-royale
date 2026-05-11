#!/usr/bin/env bash
# init-battle.sh — Scaffold a new battle directory.
#
# Usage:
#   init-battle.sh <target-dir> [--name "Battle Name"] [--rubric balanced]

set -euo pipefail

target="${1:?Usage: init-battle.sh <target-dir> [--name NAME] [--rubric NAME]}"
shift || true

name="$(basename "$target")"
rubric="balanced"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)   name="$2"; shift 2 ;;
    --rubric) rubric="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -e "$target" ]] && { echo "ERROR: $target already exists" >&2; exit 1; }

skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$target/ideas" "$target/context" "$target/output"

cat > "$target/battle.yaml" <<EOF
name: "$name"
date: "$(date +%Y-%m-%d)"

contestants:
  - id: "1"
    name: "Idea One"
    spec: "ideas/idea-1.md"
  - id: "2"
    name: "Idea Two"
    spec: "ideas/idea-2.md"
  - id: "3"
    name: "Idea Three"
    spec: "ideas/idea-3.md"
  - id: "4"
    name: "Idea Four"
    spec: "ideas/idea-4.md"

rubric: "$skill_dir/rubrics/$rubric.yaml"
context: "context/shared-context.md"

format: "bracket"
bracket:
  semifinals:
    - ["1", "3"]
    - ["2", "4"]
EOF

# Idea stubs
for i in 1 2 3 4; do
  cat > "$target/ideas/idea-$i.md" <<EOF
# Idea $i — Title

## One-line value proposition

(Required: ≤20 words.)

## Target user

## Problem and felt user value

## v1 scope

## Pricing / business model

## Competitive position

(Name specific incumbents and structural gaps.)

## Defensibility / moat

## Strategic future

(Does small open big? What's the Year 2 path?)

## Founder fit & ship-ability

## Risks
EOF
done

cat > "$target/context/shared-context.md" <<'EOF'
# Shared context for judges

Judges see this verbatim. Use it to ground "Wedge & market evidence" and "Moat & trust posture" scoring.

## Direct competitors

| Competitor | Users / ARR | Business model | Why they would NOT ship this | Why they MIGHT |
|---|---|---|---|---|
| Example Inc | 1M users, $10M ARR | Subscription | Cannibalizes core | Could ship in 6mo |

## Adjacent / cautionary comps

- (Add cautionary tales — products that died doing similar things)

## Demand evidence

- (Add specific evidence: paid users elsewhere, public threads, search trends)
- Mark anti-evidence explicitly — e.g. "no Reddit threads found of users asking for X"

## Funding climate

- (Optional: relevant capital-market context for the decision horizon)
EOF

echo "Battle scaffolded at: $target"
echo
echo "Next steps:"
echo "  1. Edit $target/battle.yaml — fill in real contestant names/specs"
echo "  2. Write $target/ideas/idea-{1,2,3,4}.md with full specs"
echo "  3. Fill $target/context/shared-context.md with real market evidence"
echo "  4. Invoke /decision-battle-royale run $target  (from Claude Code)"
echo
echo "Tip: if you already have option markdown files written, skip the stub"
echo "scaffold and use the one-shot inline mode instead:"
echo "  quick-battle.sh <idea1.md> <idea2.md> [<idea3.md> <idea4.md>]"
