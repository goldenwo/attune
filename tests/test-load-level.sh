#!/usr/bin/env bash
# test-load-level.sh — checks attune-load-level.sh in both states:
# (1) no saved preference -> a setup nudge is injected,
# (2) a saved preference file -> its contents are injected.
set -u

HOOK="$(dirname "$0")/../hooks/attune-load-level.sh"
fail=0

# Isolate HOME so the test never touches the real user's preference file.
TMP_HOME="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME"' EXIT

run_hook() { printf '{}' | HOME="$TMP_HOME" bash "$HOOK"; }

# Case 1: no preference file -> setup nudge, and valid hook JSON.
out="$(run_hook)"
if ! printf '%s' "$out" | grep -q "has not set an explanation preference"; then
    echo "FAIL: missing setup nudge when no preference file"; fail=1
fi
if ! printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
    echo "FAIL: output is not valid SessionStart hook JSON (no-file case)"; fail=1
fi

# Case 2: preference file present -> its contents are injected.
mkdir -p "$TMP_HOME/.claude/attune"
printf '# attune explanation preference\nLevel: 2 (Balanced)\n' \
    > "$TMP_HOME/.claude/attune/level.md"
out="$(run_hook)"
if ! printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "Level: 2 (Balanced)"; then
    echo "FAIL: saved preference not injected"; fail=1
fi

if [[ "$fail" -eq 0 ]]; then echo "PASS: attune-load-level.sh (2/2)"; fi
exit "$fail"
