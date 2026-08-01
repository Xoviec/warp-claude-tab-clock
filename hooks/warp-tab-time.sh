#!/bin/bash
# Stop hook — stamp the terminal tab title with the time Claude last replied.
#
# Runs after every assistant turn, so the tab reads e.g. "Adi test cyk · 14:32"
# and the timestamp is the moment of the last response.
#
# Base name resolution, first hit wins:
#   1. ~/.claude/warp-tab-name/<WARP_TERMINAL_SESSION_UUID>   — per Warp tab
#   2. ~/.claude/warp-tab-name/default                        — global fallback
#   3. basename of the project directory                      — original behaviour
#
# Warp's own tab rename (right-click → rename) takes precedence over OSC 0 and
# would hide whatever we emit, so the base name lives in a file instead.
#
# Delivery: Claude Code >= 2.1.141 accepts a `terminalSequence` field on hook output
# and writes the escape sequence to the terminal itself. Older versions reject unknown
# fields on Stop hooks, so there we write to the controlling tty instead.
set -u

TERMINAL_SEQUENCE_MIN_VERSION="2.1.141"
NAME_DIR="$HOME/.claude/warp-tab-name"

version_at_least() { # $1 >= $2 ?
    local a b i av bv
    IFS=. read -ra a <<< "$1"
    IFS=. read -ra b <<< "$2"
    for ((i = 0; i < ${#b[@]}; i++)); do
        av="${a[i]:-0}"; bv="${b[i]:-0}"
        ((av > bv)) && return 0
        ((av < bv)) && return 1
    done
    return 0
}

read_name() { # first non-empty line of $1, if it exists
    [ -f "$1" ] || return 1
    local line
    IFS= read -r line < "$1" || true
    [ -n "$line" ] || return 1
    printf '%s' "$line"
}

read_auto_name() { # "<session_id>\t<name>" written by warp-tab-autoname.sh
    [ -f "$1" ] || return 1
    local line name
    IFS= read -r line < "$1" || true
    name="${line#*$'\t'}"
    [ -n "$name" ] && [ "$name" != "$line" ] || return 1
    printf '%s' "$name"
}

uuid="${WARP_TERMINAL_SESSION_UUID:-default}"
base=""
base="$(read_name "$NAME_DIR/$uuid" || true)"
[ -n "$base" ] || base="$(read_auto_name "$NAME_DIR/$uuid.auto" || true)"
[ -n "$base" ] || base="$(read_name "$NAME_DIR/default" || true)"
[ -n "$base" ] || base="$(basename "${CLAUDE_PROJECT_DIR:-$PWD}")"

# Strip characters that would need JSON escaping; the title is cosmetic.
base="${base//\"/}"
base="${base//\\/}"
title="$(date +%H:%M) · ${base}"

raw="${CLAUDE_CODE_VERSION:-}"
ver="$(printf '%s' "$raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

emit_json() { printf '{"terminalSequence":"\\u001b]0;%s\\u0007"}\n' "$title"; }
emit_tty() {
    [ -w /dev/tty ] 2>/dev/null || return 1
    printf '\033]0;%s\007' "$title" > /dev/tty 2>/dev/null
}

if [ -n "$ver" ]; then
    if version_at_least "$ver" "$TERMINAL_SEQUENCE_MIN_VERSION"; then
        emit_json
    else
        emit_tty || true
    fi
else
    emit_tty || emit_json
fi
exit 0
