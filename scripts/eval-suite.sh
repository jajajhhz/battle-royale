#!/usr/bin/env bash
# eval-suite.sh — Run the eval suite at evals/* and write EVAL_RESULTS.md.
#
# Usage:
#   eval-suite.sh                              # run all auto evals
#   eval-suite.sh --eval <name>                # run one eval by directory name
#   eval-suite.sh --include-manual             # also run live-subagent evals
#   eval-suite.sh --no-report                  # skip writing EVAL_RESULTS.md
#
# Each eval is a directory under evals/ with an expected.json file
# describing assertions. See evals/README.md for the schema.
#
# Exit code:
#   0  all evals passed
#   1  at least one eval failed
#   2  fatal error (script can't find evals dir, expected.json malformed)

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
evals_dir="$repo_root/evals"
report_path="$repo_root/EVAL_RESULTS.md"

include_manual=false
single_eval=""
write_report=true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --include-manual) include_manual=true; shift ;;
    --eval)           single_eval="$2"; shift 2 ;;
    --no-report)      write_report=false; shift ;;
    -h|--help)
      sed -n '2,20p' "$0" >&2
      exit 0
      ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -d "$evals_dir" ]] || { echo "ERROR: no evals/ directory at $repo_root" >&2; exit 2; }

# --- Dispatch to Python for the actual eval logic --------------------------
# Bash is fine for orchestration, but the assertion dispatch + nested-field
# extraction is much cleaner in Python.

python3 - "$repo_root" "$evals_dir" "$report_path" "$include_manual" "$single_eval" "$write_report" <<'PYEOF'
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

repo_root = Path(sys.argv[1])
evals_dir = Path(sys.argv[2])
report_path = Path(sys.argv[3])
include_manual = sys.argv[4] == "true"
single_eval = sys.argv[5]
write_report = sys.argv[6] == "true"

scripts_dir = repo_root / "scripts"


# --- Helpers ----------------------------------------------------------------
def get_nested(obj, dotted_key):
    """Walk a dotted-key path into a dict/json structure."""
    parts = dotted_key.split(".")
    for p in parts:
        if isinstance(obj, dict) and p in obj:
            obj = obj[p]
        else:
            return None
    return obj


def run_script(script, *args, env=None):
    """Run a script in scripts/, return (exit_code, stdout, stderr)."""
    cmd = ["bash", str(scripts_dir / script)] + list(args)
    proc = subprocess.run(
        cmd,
        env={**os.environ, **(env or {})},
        capture_output=True, text=True,
    )
    return proc.returncode, proc.stdout, proc.stderr


# --- Assertion handlers -----------------------------------------------------
def assert_parser_extracts(eval_dir, a):
    """Run parse-verdict.sh against a fixture and compare extracted fields."""
    fixture = eval_dir / a["fixture"]
    rubric = repo_root / a["rubric"]
    expect = a["expect"]
    rc, out, err = run_script("parse-verdict.sh", str(fixture), str(rubric))
    if rc != 0:
        return [(False, f"parse-verdict.sh exited {rc}: {err.strip()[:200]}")]
    try:
        parsed = json.loads(out)
    except json.JSONDecodeError as e:
        return [(False, f"parse-verdict.sh stdout was not valid JSON: {e}")]
    results = []
    for key, expected in expect.items():
        actual = get_nested(parsed, key)
        if actual == expected:
            results.append((True, f"{key} == {expected!r}"))
        else:
            results.append((False, f"{key} expected {expected!r}, got {actual!r}"))
    return results


def assert_audit_recommendation(eval_dir, a):
    """Run audit-verdict.sh against fixtures and compare extracted fields."""
    audit_fix = eval_dir / a["audit_fixture"]
    verdict_fix = eval_dir / a["verdict_fixture"]
    expect = a["expect"]
    rc, out, err = run_script("audit-verdict.sh", str(audit_fix), str(verdict_fix))
    # audit-verdict.sh returns 0 (PASS), 1 (RETRY), 2 (malformed). For an eval,
    # we don't gate on exit code — we read the JSON and check field-by-field.
    if rc == 2:
        return [(False, f"audit-verdict.sh reported malformed: {err.strip()[:200]}")]
    try:
        parsed = json.loads(out)
    except json.JSONDecodeError as e:
        return [(False, f"audit-verdict.sh stdout was not valid JSON: {e}")]
    results = []
    for key, expected in expect.items():
        # Special: aggregate_min etc — treat suffix _min as ">=" comparison
        if key.endswith("_min"):
            base_key = key[: -len("_min")]
            actual = get_nested(parsed, base_key)
            if actual is not None and actual >= expected:
                results.append((True, f"{base_key} >= {expected} (actual {actual})"))
            else:
                results.append((False, f"{base_key} expected >= {expected}, got {actual!r}"))
        else:
            actual = get_nested(parsed, key)
            if actual == expected:
                results.append((True, f"{key} == {expected!r}"))
            else:
                results.append((False, f"{key} expected {expected!r}, got {actual!r}"))
    return results


def assert_rendered_prompt_contains(eval_dir, a):
    """Render a prompt template and assert it contains expected strings."""
    template = repo_root / a["template"]
    env = a["env"]
    expect = a["expect"]
    rc, out, err = run_script("render-prompt.sh", str(template), env=env)
    if rc != 0:
        return [(False, f"render-prompt.sh exited {rc}: {err.strip()[:200]}")]
    results = []
    for needle in expect.get("contains_all", []):
        if needle in out:
            results.append((True, f"contains {needle!r}"))
        else:
            results.append((False, f"missing {needle!r} in rendered prompt"))
    if "delimiter_count_min" in expect:
        delim = "════════════════ DOCUMENT START ════════════════"
        actual = out.count(delim)
        if actual >= expect["delimiter_count_min"]:
            results.append((True, f"delimiter count {actual} >= {expect['delimiter_count_min']}"))
        else:
            results.append((False, f"delimiter count {actual} < {expect['delimiter_count_min']}"))
    return results


def assert_renders_clean(eval_dir, a):
    """Render a template and check for unsubstituted {ALL_CAPS} placeholders."""
    template = repo_root / a["template"]
    env = a["env"]
    expect = a["expect"]
    rc, out, err = run_script("render-prompt.sh", str(template), env=env)
    if rc != 0:
        return [(False, f"render-prompt.sh exited {rc}: {err.strip()[:200]}")]
    results = []
    if not out.strip():
        return [(False, "rendered output is empty")]
    if "first_header_contains" in expect:
        first_lines = out.split("\n", 5)
        header_line = next((l for l in first_lines if l.startswith("#")), "")
        if expect["first_header_contains"] in header_line:
            results.append((True, f"first header contains {expect['first_header_contains']!r}"))
        else:
            results.append((False, f"first header missing {expect['first_header_contains']!r} (got {header_line!r})"))
    if expect.get("no_unsubstituted_placeholders"):
        # Match ALL-CAPS placeholders like {IDEA_SPEC}, {OUTPUT_PATH}.
        # Don't false-positive on legitimate uses like `{N}`.
        leftover = re.findall(r"\{[A-Z][A-Z_]{2,}\}", out)
        if not leftover:
            results.append((True, "no unsubstituted placeholders"))
        else:
            unique = sorted(set(leftover))
            results.append((False, f"unsubstituted placeholders: {unique}"))
    return results


def assert_frontmatter_valid(eval_dir, a):
    """Parse SKILL.md frontmatter and assert spec compliance."""
    file_path = repo_root / a["file"]
    expect = a["expect"]
    if not file_path.exists():
        return [(False, f"file not found: {file_path}")]
    text = file_path.read_text(encoding="utf-8")
    fm_match = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if not fm_match:
        return [(False, "no YAML frontmatter at top of file")]
    fm_text = fm_match.group(1)
    # Parse simple "key: value" pairs (only what we need for assertions).
    fields = {}
    for line in fm_text.splitlines():
        m = re.match(r"^([a-z][a-z0-9_-]*):\s*(.*)$", line)
        if m:
            fields[m.group(1)] = m.group(2).strip().strip('"\'')
    results = []
    if "name" in expect and fields.get("name") == expect["name"]:
        results.append((True, f"name == {expect['name']!r}"))
    elif "name" in expect:
        results.append((False, f"name expected {expect['name']!r}, got {fields.get('name')!r}"))
    if "name_max_chars" in expect:
        n = len(fields.get("name", ""))
        if n <= expect["name_max_chars"]:
            results.append((True, f"name length {n} <= {expect['name_max_chars']}"))
        else:
            results.append((False, f"name length {n} > {expect['name_max_chars']}"))
    if "name_pattern" in expect:
        if re.match(expect["name_pattern"], fields.get("name", "")):
            results.append((True, f"name matches pattern {expect['name_pattern']!r}"))
        else:
            results.append((False, f"name {fields.get('name')!r} does not match {expect['name_pattern']!r}"))
    if expect.get("has_description"):
        if "description" in fields and fields["description"]:
            results.append((True, "description present"))
        else:
            results.append((False, "description missing or empty"))
    if "description_max_chars" in expect:
        d = len(fields.get("description", ""))
        if d <= expect["description_max_chars"]:
            results.append((True, f"description length {d} <= {expect['description_max_chars']}"))
        else:
            results.append((False, f"description length {d} > {expect['description_max_chars']}"))
    if expect.get("has_license"):
        if "license" in fields and fields["license"]:
            results.append((True, f"license == {fields['license']!r}"))
        else:
            results.append((False, "license field missing"))
    if expect.get("no_unknown_fields"):
        known = {"name", "description", "license", "compatibility", "metadata", "allowed-tools"}
        unknown = sorted(set(fields.keys()) - known)
        if not unknown:
            results.append((True, "no unknown frontmatter fields"))
        else:
            results.append((False, f"unknown frontmatter fields: {unknown}"))
    if "description_contains_any" in expect:
        desc = fields.get("description", "")
        matches = [phrase for phrase in expect["description_contains_any"] if phrase in desc]
        if matches:
            results.append((True, f"description contains trigger phrase: {matches[0]!r}"))
        else:
            results.append((False, f"description missing all trigger phrases: {expect['description_contains_any']}"))
    return results


HANDLERS = {
    "parser_extracts": assert_parser_extracts,
    "audit_recommendation": assert_audit_recommendation,
    "rendered_prompt_contains": assert_rendered_prompt_contains,
    "renders_clean": assert_renders_clean,
    "frontmatter_valid": assert_frontmatter_valid,
}


# --- Discover and run evals -------------------------------------------------
eval_dirs = sorted(
    p for p in evals_dir.iterdir()
    if p.is_dir() and (p / "expected.json").exists()
)
if single_eval:
    eval_dirs = [p for p in eval_dirs if p.name == single_eval]
    if not eval_dirs:
        print(f"ERROR: no eval named {single_eval!r}", file=sys.stderr)
        sys.exit(2)

results_by_eval = []
for eval_dir in eval_dirs:
    expected = json.loads((eval_dir / "expected.json").read_text())
    is_manual = expected.get("manual", False)
    if is_manual and not include_manual:
        results_by_eval.append({
            "name": expected.get("name", eval_dir.name),
            "dir": eval_dir.name,
            "category": expected.get("category", "?"),
            "skipped": True,
            "skip_reason": "manual — run with --include-manual",
            "checks": [],
        })
        continue

    eval_results = {
        "name": expected.get("name", eval_dir.name),
        "dir": eval_dir.name,
        "category": expected.get("category", "?"),
        "skipped": False,
        "checks": [],
    }
    for a in expected.get("assertions", []):
        handler = HANDLERS.get(a["type"])
        if not handler:
            eval_results["checks"].append({
                "type": a["type"],
                "passed": False,
                "message": f"unknown assertion type: {a['type']}",
            })
            continue
        try:
            check_results = handler(eval_dir, a)
        except Exception as e:
            check_results = [(False, f"handler raised: {type(e).__name__}: {e}")]
        for passed, msg in check_results:
            eval_results["checks"].append({
                "type": a["type"],
                "passed": passed,
                "message": msg,
            })
    results_by_eval.append(eval_results)


# --- Report -----------------------------------------------------------------
total_checks = sum(len(e["checks"]) for e in results_by_eval if not e["skipped"])
passed_checks = sum(
    1 for e in results_by_eval if not e["skipped"]
    for c in e["checks"] if c["passed"]
)
failed_checks = total_checks - passed_checks
skipped_evals = sum(1 for e in results_by_eval if e["skipped"])

print(f"\n{'=' * 60}")
print(f"  EVAL SUITE  —  {passed_checks}/{total_checks} checks passed", end="")
if skipped_evals:
    print(f"  ({skipped_evals} eval(s) skipped — manual)", end="")
print()
print('=' * 60)
for e in results_by_eval:
    if e["skipped"]:
        print(f"  [SKIP] {e['dir']}  ({e['skip_reason']})")
        continue
    eval_passed = all(c["passed"] for c in e["checks"])
    marker = "[PASS]" if eval_passed else "[FAIL]"
    print(f"  {marker} {e['dir']}  ({e['category']})")
    for c in e["checks"]:
        sub = "    ✓" if c["passed"] else "    ✗"
        print(f"{sub} {c['type']}: {c['message']}")
print()


# --- Write EVAL_RESULTS.md --------------------------------------------------
if write_report:
    lines = []
    lines.append("# Eval results")
    lines.append("")
    lines.append(f"_Generated by `scripts/eval-suite.sh` on {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}._")
    lines.append("")
    lines.append(f"**{passed_checks} / {total_checks} checks passed.**")
    if skipped_evals:
        lines.append(f"{skipped_evals} eval(s) skipped (manual — run with `--include-manual`).")
    lines.append("")
    lines.append("| Eval | Category | Status | Checks |")
    lines.append("|---|---|---|---|")
    for e in results_by_eval:
        if e["skipped"]:
            lines.append(f"| `{e['dir']}` | {e['category']} | SKIP (manual) | — |")
            continue
        eval_passed = all(c["passed"] for c in e["checks"])
        c_passed = sum(1 for c in e["checks"] if c["passed"])
        c_total = len(e["checks"])
        status = "PASS ✓" if eval_passed else "FAIL ✗"
        lines.append(f"| `{e['dir']}` | {e['category']} | {status} | {c_passed} / {c_total} |")
    lines.append("")
    lines.append("## Per-eval detail")
    lines.append("")
    for e in results_by_eval:
        lines.append(f"### `{e['dir']}` — {e['name']}")
        lines.append("")
        if e["skipped"]:
            lines.append(f"_Skipped: {e['skip_reason']}_")
            lines.append("")
            continue
        for c in e["checks"]:
            mark = "✓" if c["passed"] else "✗"
            lines.append(f"- {mark} `{c['type']}` — {c['message']}")
        lines.append("")
    report_path.write_text("\n".join(lines) + "\n")
    print(f"Report written: {report_path}")


sys.exit(0 if failed_checks == 0 else 1)
PYEOF
