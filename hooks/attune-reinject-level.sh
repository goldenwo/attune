#!/usr/bin/env bash
# attune-reinject-level.sh — UserPromptSubmit hook. Re-states the reader's saved
# explanation preference every Nth prompt so it survives a long session.
#
# Why this exists: attune-load-level.sh injects the preference once, at
# SessionStart. One injection at turn 0 is buried by turn 40 under tool output,
# project orientation and CLAUDE.md, and the reader sees the preference quietly
# stop being honoured. This is the same decay the claude-harness-toolkit's
# focus-check hook was built to fix, and this hook mirrors its counter-mod
# idiom (per-session counter in TMPDIR, atomic temp+rename write, emit on
# COUNTER % EVERY == 0).
#
# Claude Code users may not need this: its native output styles ship with every
# request and carry their own per-turn reminder. Codex has no such mechanism, so
# on that side this hook is the only thing keeping the preference alive. It is
# registered for both because the preference file is shared and the cost is a
# few dozen tokens every Nth prompt.
#
# Knobs (env wins over config file):
#   ATTUNE_EVERY=<n>      re-inject every n prompts (default 5; n<1 disables)
#   ATTUNE_DISABLE=1      never emit
#   ~/.claude/attune/config.json  {"every": 5, "disable": false}
#
# Output JSON shape (per Claude Code hooks reference):
#   {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
#                           "additionalContext": "..."}}
set -u

# Fail-open: without jq we cannot read the payload or safely emit JSON
# (matches attune-load-level.sh).
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# Builtin read, not $(cat): this hook fires on EVERY prompt, and on Windows each
# fork costs ~30ms (bash) to ~90ms (jq) — see the fork budget note at the bottom.
PAYLOAD=""
IFS= read -r -d '' PAYLOAD 2>/dev/null || true

LEVEL_FILE="${HOME}/.claude/attune/level.md"
CONFIG_FILE="${HOME}/.claude/attune/config.json"

# Nothing saved yet — attune-load-level.sh emits the setup nudge at SessionStart
# and there is no preference to restate. Costs nothing on an uninstalled setup.
[ -f "$LEVEL_FILE" ] || exit 0

# ---------------------------------------------------------------- knobs
EVERY=5
DISABLE=0

if [ -f "$CONFIG_FILE" ]; then
    _cfg_every="$(jq -r '.every // empty' "$CONFIG_FILE" 2>/dev/null || true)"
    case "$_cfg_every" in
        ''|*[!0-9-]*) ;;
        *) EVERY="$_cfg_every" ;;
    esac
    _cfg_disable="$(jq -r '.disable // empty' "$CONFIG_FILE" 2>/dev/null || true)"
    [ "$_cfg_disable" = "true" ] && DISABLE=1
fi

# Env overrides the file, so a single session can differ from the saved default.
if [ -n "${ATTUNE_EVERY:-}" ]; then
    case "$ATTUNE_EVERY" in
        ''|*[!0-9-]*) ;;
        *) EVERY="$ATTUNE_EVERY" ;;
    esac
fi
[ "${ATTUNE_DISABLE:-}" = "1" ] && DISABLE=1

[ "$DISABLE" -eq 1 ] && exit 0
# Both knob sources are filtered above, but neither rejects every non-integer
# (e.g. "1-2"). Re-validate before arithmetic so a malformed knob degrades to
# the default instead of crashing the modulo.
case "${EVERY#-}" in
    ''|*[!0-9]*) EVERY=5 ;;
esac
# A non-positive interval is the documented off switch, and guards the modulo
# below against a division by zero.
[ "$EVERY" -lt 1 ] 2>/dev/null && exit 0

# ---------------------------------------------------------------- counter
SESSION_ID=""
# Bash regex, not jq: jq is the single most expensive fork here (~90ms measured on
# Windows) and it would run on every fire just to read one flat string. The emit
# path below still uses jq, where correct JSON escaping actually matters.
if [[ "$PAYLOAD" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]*)\" ]]; then
    SESSION_ID="${BASH_REMATCH[1]}"
fi
# Filename hygiene: session_id reaches us from the harness, so strip anything
# that could escape the counter path. Empty ids share one counter — parallel
# sessions then advance it together, which costs an occasional off-cadence
# re-injection and nothing else.
SESSION_ID="${SESSION_ID//[^A-Za-z0-9._-]/}"
[ -n "$SESSION_ID" ] || SESSION_ID="nosession"

TMP="${TMPDIR:-/tmp}"
COUNTER_FILE="${TMP}/.attune-reinject-${SESSION_ID}"

COUNTER=0
if [ -f "$COUNTER_FILE" ]; then
    read -r COUNTER < "$COUNTER_FILE" 2>/dev/null || COUNTER=0
    case "$COUNTER" in
        ''|*[!0-9]*) COUNTER=0 ;;
    esac
fi
COUNTER=$((COUNTER + 1))

# Atomic write (temp+rename): a hook killed mid-write must not leave a partial
# counter that parses as 0 and restarts the cadence.
TMP_COUNTER="${COUNTER_FILE}.tmp.$$"
if ! { printf '%d\n' "$COUNTER" > "$TMP_COUNTER" 2>/dev/null && mv "$TMP_COUNTER" "$COUNTER_FILE" 2>/dev/null; }; then
    rm -f "$TMP_COUNTER" 2>/dev/null
    # Without persistence the counter resets to 1 every fire and this hook never
    # emits. Warn once per session so the failure is visible rather than silent.
    WARN_MARKER="${TMP}/.attune-reinject-warned-${SESSION_ID}"
    if [ ! -f "$WARN_MARKER" ]; then
        echo "WARN: attune-reinject-level.sh cannot persist its counter to ${COUNTER_FILE} — the preference will not be re-stated. dir=${TMP}" >&2
        touch "$WARN_MARKER" 2>/dev/null
    fi
fi

if [ $((COUNTER % EVERY)) -ne 0 ]; then
    exit 0
fi

# ---------------------------------------------------------------- emit
# Compact form, not the SessionStart prose: this fires for the whole session, so
# every token is paid repeatedly. Drop the file's markdown header and blanks and
# join what is left ("Level: ...", an optional "Shape: ...") onto one line.
SUMMARY="$(sed -e 's/\r$//' -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$LEVEL_FILE" 2>/dev/null \
    | awk 'NR>1{printf "; "} {printf "%s", $0} END{print ""}' 2>/dev/null)"
[ -n "$SUMMARY" ] || exit 0

CONTEXT="$(printf 'Reminder — the reader'"'"'s saved explanation preference (attune): %s. Match this reply to it.' "$SUMMARY")"

jq -n --arg ctx "$CONTEXT" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $ctx}}'

exit 0

# Fork budget (measured on Windows, 2026-09-14, 20 fires): bare bash spawn ~30ms,
# one jq spawn ~88ms. A non-emitting fire — 4 out of every 5 — now forks only `mv`
# for the atomic counter write; everything else on that path is a bash builtin. The
# sed/awk/jq trio runs only on the fire that actually emits. Before this pass the
# hook averaged 283ms per fire; do not reintroduce a per-fire `cat`, `tr` or `jq`.
