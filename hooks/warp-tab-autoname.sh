#!/bin/bash
# UserPromptSubmit hook — derive a tab base name from the first prompt of a session.
#
# Writes ~/.claude/warp-tab-name/<WARP_TERMINAL_SESSION_UUID>.auto containing:
#   <session_id>\t<name>
#
# The session id is stored alongside the name so the name stays stable for the
# whole session, but a new Claude session in the same Warp tab renames it.
# An explicit name (set via `tabname` or written directly) always wins — that
# file is checked first by warp-tab-time.sh.
#
# Must print nothing: stdout from a UserPromptSubmit hook is injected as context.
set -u

NAME_DIR="$HOME/.claude/warp-tab-name"
MAX_LEN=28

uuid="${WARP_TERMINAL_SESSION_UUID:-default}"
target="$NAME_DIR/$uuid.auto"

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)"
[ -n "$session_id" ] || exit 0
[ -n "$prompt" ] || exit 0

# Keep the name from the session's first prompt; later prompts don't rename.
if [ -f "$target" ]; then
    IFS=$'\t' read -r prev_session _ < "$target" || true
    [ "$prev_session" = "$session_id" ] && exit 0
fi

# Slash commands describe the tab poorly — let the next real prompt name it.
case "$prompt" in
    /*) exit 0 ;;
esac

# First line, collapsed whitespace, trimmed, truncated.
name="$(printf '%s' "$prompt" | head -1 | tr -s '[:space:]' ' ')"
name="${name# }"
name="${name% }"
[ -n "$name" ] || exit 0
if [ "${#name}" -gt "$MAX_LEN" ]; then
    name="${name:0:$MAX_LEN}…"
fi

mkdir -p "$NAME_DIR" || exit 0
printf '%s\t%s\n' "$session_id" "$name" > "$target" 2>/dev/null
exit 0
