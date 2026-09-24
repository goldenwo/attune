#!/usr/bin/env bash
# attune-load-level.sh — SessionStart hook. Reads the user's saved
# explanation level and injects it so every reply is tuned to that level.
# If no level is saved yet, injects a nudge telling the model to run the
# attune skill and ask the two setup questions.
#
# Output JSON shape (per Claude Code hooks reference):
#   {"hookSpecificOutput": {"hookEventName": "SessionStart",
#                           "additionalContext": "..."}}
set -u

# Fail-open: without jq we cannot safely emit JSON, so skip silently
# (matches session-start-orient.sh).
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# Drain stdin (SessionStart input JSON); not needed, keeps the pipe clean.
cat >/dev/null 2>&1 || true

LEVEL_FILE="${HOME}/.claude/attune/level.md"

# Path to show the model for the Write tool. On Windows git-bash, convert the
# POSIX path to a native Windows path so Write/Read resolve it; elsewhere the
# POSIX path is already correct.
if command -v cygpath >/dev/null 2>&1; then
    LEVEL_FILE_NATIVE="$(cygpath -w "$LEVEL_FILE" 2>/dev/null || printf '%s' "$LEVEL_FILE")"
else
    LEVEL_FILE_NATIVE="$LEVEL_FILE"
fi

if [[ -f "$LEVEL_FILE" ]]; then
    LEVEL_CONTENT="$(cat "$LEVEL_FILE")"
    CONTEXT="$(printf 'The reader has a saved explanation preference (attune plugin):\n\n%s\n\nMatch every reply to this preference. If they ask to go simpler, shorter, deeper, or for more detail, adjust now and save the updated preference to: %s' "$LEVEL_CONTENT" "$LEVEL_FILE_NATIVE")"
else
    CONTEXT="$(printf 'The reader has not set an explanation preference yet (attune plugin). Early in the conversation, use the attune skill to ask the one short setup question, then save their answer to: %s' "$LEVEL_FILE_NATIVE")"
fi

jq -n --arg ctx "$CONTEXT" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}'

exit 0
