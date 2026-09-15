#!/usr/bin/env bash
# codex/run-hook.sh — Codex CLI launcher for the shared hooks/<hook>.sh scripts.
#
# Codex and Claude Code send byte-compatible hook payloads for everything EXCEPT
# file edits: Claude sends Edit/Write/MultiEdit with tool_input.file_path +
# content/new_string, Codex sends tool_name "apply_patch" with the whole patch text
# in tool_input.command. Rather than teach five hooks a second shape (and re-prove
# every suite + the matcher differential), this launcher normalises the payload:
#
#   tool_name != apply_patch  → exec hooks/<hook>.sh with stdin passed through untouched
#   tool_name == apply_patch  → codex/adapt-payload.py splits the patch into one
#                               Claude-shaped Write/Edit payload per touched file and
#                               the hook runs once per payload
#
# Exit code: the highest exit code any run produced (2 = block wins, as in Claude).
# Stdout: only the FIRST non-empty stdout is forwarded (Codex parses a single JSON
# document); stderr is forwarded from every run (it is the block reason on exit 2).
# Unparseable patches pass through unchanged — the gate still sees the raw payload.
#
# Invoked by codex/hooks.json (POSIX: `bash ${PLUGIN_ROOT}/codex/run-hook.sh <hook>.sh`)
# and by codex/run-hook.ps1 on Windows, which resolves git-bash first.
set -u

HOOK="${1:-}"
[ -n "$HOOK" ] || exit 0
case "$HOOK" in */*|*..*) exit 0 ;; esac   # hook names only, never paths

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}}"
ROOT="${ROOT//\\//}"
export CLAUDE_PLUGIN_ROOT="$ROOT"

HOOK_PATH="$ROOT/hooks/$HOOK"
[ -f "$HOOK_PATH" ] || exit 0
ADAPTER="$SCRIPT_DIR/adapt-payload.py"

# Hook-env parity (2026-09-10). Claude Code exports its settings.json `env` block
# (YAGNI_MODE, CLAUDE_HOOK_LOG, PYTHONUTF8, UM_SERVER_URL, ...) to hooks AND the
# model's shell; Codex gives hooks only its own process env, so env-gated hooks
# (session-start-yagni is silent unless YAGNI_MODE=on) diverge. bin/codex-bootstrap.sh
# renders that block to a user-owned file; sourcing it here is the hook-side twin of
# Codex's [shell_environment_policy.set] (the model-shell side). Absent file = no-op.
HOOK_ENV="${CODEX_HOME:-$HOME/.codex}/harness-hook-env.sh"
if [ -f "$HOOK_ENV" ]; then
    # shellcheck disable=SC1090
    . "$HOOK_ENV"
fi

PAYLOAD="$(cat 2>/dev/null || true)"

# Fast path: not a file edit (or no adapter shipped, e.g. the attune plugin).
TOOL_NAME=""
if [ -n "$PAYLOAD" ] && command -v jq >/dev/null 2>&1; then
    TOOL_NAME="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null || true)"
fi
if [ "$TOOL_NAME" != "apply_patch" ] || [ ! -f "$ADAPTER" ]; then
    printf '%s' "$PAYLOAD" | bash "$HOOK_PATH"
    exit $?
fi

# Python for the adapter. MUST be a VALIDATED interpreter, not the first name that
# exists: on Windows `python`/`python3` can be Microsoft Store stubs AND `py` can be a
# launcher whose default registration points at a deleted directory (measured
# 2026-09-14 -- a stale HKCU PythonCore\3.14 entry made bare `py` fail with "Unable to
# create process"). An unvalidated pick made the adapter return nothing, run-hook fell
# back to the RAW apply_patch payload, and secret-scan stopped being able to block a
# planted key on Codex -- a gate that silently could not fail. hooks/_python.sh probes
# each candidate with a real `--version` and honours a preset PYTHON_BIN, so the shared
# resolver is the single source of truth here too.
# shellcheck disable=SC1091
. "$ROOT/hooks/_python.sh" 2>/dev/null || true
PY=""
if command -v ensure_python >/dev/null 2>&1 && ensure_python 2>/dev/null; then
    PY="${PYTHON_BIN:-}"
fi
if [ -z "$PY" ]; then
    for c in py python3 python; do
        if command -v "$c" >/dev/null 2>&1 && "$c" --version >/dev/null 2>&1; then PY="$c"; break; fi
    done
fi
if [ -z "$PY" ]; then
    printf '%s' "$PAYLOAD" | bash "$HOOK_PATH"
    exit $?
fi

ADAPTED="$(printf '%s' "$PAYLOAD" | "$PY" "$ADAPTER" 2>/dev/null)" || ADAPTED=""
if [ -z "$ADAPTED" ]; then
    printf '%s' "$PAYLOAD" | bash "$HOOK_PATH"
    exit $?
fi

MAX_RC=0
FIRST_OUT=""
while IFS= read -r line; do
    [ -n "$line" ] || continue
    OUT="$(printf '%s' "$line" | bash "$HOOK_PATH")"
    RC=$?
    if [ -z "$FIRST_OUT" ] && [ -n "$OUT" ]; then FIRST_OUT="$OUT"; fi
    [ "$RC" -gt "$MAX_RC" ] && MAX_RC=$RC
done <<EOF
$ADAPTED
EOF
[ -n "$FIRST_OUT" ] && printf '%s\n' "$FIRST_OUT"
exit "$MAX_RC"
