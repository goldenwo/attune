#!/usr/bin/env bash
# test-reinject-level.sh — checks attune-reinject-level.sh: the cadence (emit on
# every Nth prompt and no other), the knobs, the no-preference-file case, and the
# compact one-line summary it emits.
set -u

HOOK="$(dirname "$0")/../hooks/attune-reinject-level.sh"
fail=0

TMP_HOME="$(mktemp -d)"
TMP_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMP_HOME" "$TMP_TMPDIR"' EXIT

SID="test-session-0001"

# One fire of the hook, with HOME and TMPDIR isolated so neither the real
# preference file nor the real counter is touched. Extra env comes from argv.
run_hook() {
    printf '{"session_id":"%s"}' "$SID" \
        | env HOME="$TMP_HOME" TMPDIR="$TMP_TMPDIR" "$@" bash "$HOOK"
}

reset_counter() { rm -f "$TMP_TMPDIR"/.attune-reinject-* 2>/dev/null; }

write_level() {
    mkdir -p "$TMP_HOME/.claude/attune"
    printf '%s\n' "$@" > "$TMP_HOME/.claude/attune/level.md"
}

# Case 1: no preference file -> silent (nothing to restate).
out="$(run_hook ATTUNE_X=1)"
if [ -n "$out" ]; then
    echo "FAIL: emitted with no preference file"; fail=1
fi

# Case 2: default cadence is every 5th prompt, and only the 5th.
write_level '# attune explanation preference' 'Level: 1 (Just the answer) — technical'
reset_counter
emitted=""
for i in 1 2 3 4 5; do
    out="$(run_hook ATTUNE_X=1)"
    [ -n "$out" ] && emitted="$emitted $i"
done
if [ "$emitted" != " 5" ]; then
    echo "FAIL: default cadence emitted on prompts [$emitted], expected [ 5]"; fail=1
fi

# Case 3: the emission is valid UserPromptSubmit hook JSON carrying the level.
reset_counter
out=""
for _ in 1 2 3 4 5; do out="$(run_hook ATTUNE_X=1)"; done
if ! printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null 2>&1; then
    echo "FAIL: emission is not valid UserPromptSubmit hook JSON"; fail=1
fi
if ! printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "Level: 1 (Just the answer)"; then
    echo "FAIL: emission does not carry the saved level"; fail=1
fi
# The markdown header is dropped — this fires all session, so it must stay compact.
if printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q "# attune"; then
    echo "FAIL: emission kept the markdown header"; fail=1
fi

# Case 4: a Shape: line rides along, joined onto the same line as the level.
write_level '# attune explanation preference' 'Level: 1 (Just the answer)' 'Shape: no preamble, no recap'
reset_counter
out=""
for _ in 1 2 3 4 5; do out="$(run_hook ATTUNE_X=1)"; done
ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
if ! printf '%s' "$ctx" | grep -q "Level: 1 (Just the answer); Shape: no preamble, no recap"; then
    echo "FAIL: Shape line not joined onto the summary (got: $ctx)"; fail=1
fi
if [ "$(printf '%s' "$ctx" | wc -l)" -ne 0 ]; then
    echo "FAIL: emission summary is not a single line"; fail=1
fi

# Case 5: ATTUNE_EVERY changes the cadence.
write_level '# attune explanation preference' 'Level: 2 (Balanced)'
reset_counter
emitted=""
for i in 1 2 3 4; do
    out="$(run_hook ATTUNE_EVERY=2)"
    [ -n "$out" ] && emitted="$emitted $i"
done
if [ "$emitted" != " 2 4" ]; then
    echo "FAIL: ATTUNE_EVERY=2 emitted on [$emitted], expected [ 2 4]"; fail=1
fi

# Case 6: ATTUNE_DISABLE=1 silences it entirely.
reset_counter
emitted=""
for i in 1 2 3 4 5 6; do
    out="$(run_hook ATTUNE_DISABLE=1)"
    [ -n "$out" ] && emitted="$emitted $i"
done
if [ -n "$emitted" ]; then
    echo "FAIL: ATTUNE_DISABLE=1 still emitted on [$emitted]"; fail=1
fi

# Case 7: config file supplies the cadence, and env beats the file.
mkdir -p "$TMP_HOME/.claude/attune"
printf '{"every": 3}\n' > "$TMP_HOME/.claude/attune/config.json"
reset_counter
emitted=""
for i in 1 2 3; do
    out="$(run_hook ATTUNE_X=1)"
    [ -n "$out" ] && emitted="$emitted $i"
done
if [ "$emitted" != " 3" ]; then
    echo "FAIL: config every=3 emitted on [$emitted], expected [ 3]"; fail=1
fi
reset_counter
emitted=""
for i in 1 2; do
    out="$(run_hook ATTUNE_EVERY=2)"
    [ -n "$out" ] && emitted="$emitted $i"
done
if [ "$emitted" != " 2" ]; then
    echo "FAIL: env did not override config every (emitted [$emitted], expected [ 2])"; fail=1
fi

# Case 8: a malformed interval degrades to the default instead of crashing.
rm -f "$TMP_HOME/.claude/attune/config.json"
reset_counter
emitted=""
err=""
for i in 1 2 3 4 5; do
    out="$(run_hook ATTUNE_EVERY=1-2 2>"$TMP_TMPDIR/err")"
    [ -s "$TMP_TMPDIR/err" ] && err="$err $i"
    [ -n "$out" ] && emitted="$emitted $i"
done
if [ "$emitted" != " 5" ]; then
    echo "FAIL: malformed ATTUNE_EVERY did not fall back to 5 (emitted [$emitted])"; fail=1
fi
if [ -n "$err" ]; then
    echo "FAIL: malformed ATTUNE_EVERY wrote to stderr on prompts [$err]"; fail=1
fi

# Case 9: a non-positive interval is the documented off switch.
reset_counter
emitted=""
for i in 1 2 3 4 5; do
    out="$(run_hook ATTUNE_EVERY=0)"
    [ -n "$out" ] && emitted="$emitted $i"
done
if [ -n "$emitted" ]; then
    echo "FAIL: ATTUNE_EVERY=0 still emitted on [$emitted]"; fail=1
fi

if [ "$fail" -eq 0 ]; then echo "PASS: attune-reinject-level.sh (9/9)"; fi
exit "$fail"
