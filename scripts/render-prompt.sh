#!/usr/bin/env bash
# render-prompt.sh — Substitute {PLACEHOLDER} tokens in a template with env vars.
#
# Usage:
#   IDEA_NAME="..." IDEA_SPEC="..." render-prompt.sh <template-file> > rendered.md
#
# All env vars matching {NAME} placeholders in the template are substituted.
# Multi-line values are supported via Python substitution (no shell escaping issues).
#
# Exit codes:
#   0  success
#   1  template not found or unreadable
#   2  unsubstituted placeholders remain (warns but does not fail)

set -euo pipefail

template="${1:?Usage: render-prompt.sh <template-file>}"
[[ -f "$template" ]] || { echo "ERROR: template not found: $template" >&2; exit 1; }

# Use Python for safe multi-line substitution. macOS ships python3 by default.
python3 - "$template" <<'PYEOF'
import os, re, sys

template_path = sys.argv[1]
with open(template_path, encoding="utf-8") as f:
    content = f.read()

# Find all {PLACEHOLDER} tokens (uppercase + underscores)
placeholders = sorted(set(re.findall(r"\{([A-Z][A-Z0-9_]*)\}", content)))

for ph in placeholders:
    value = os.environ.get(ph, "")
    content = content.replace("{" + ph + "}", value)

# Warn about any remaining placeholders (env var was not set)
remaining = re.findall(r"\{([A-Z][A-Z0-9_]*)\}", content)
if remaining:
    sys.stderr.write(
        "WARN: unsubstituted placeholders: " + ", ".join(sorted(set(remaining))) + "\n"
    )

sys.stdout.write(content)
PYEOF
