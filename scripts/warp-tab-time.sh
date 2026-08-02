#!/bin/bash
# Stop hook — stamp the terminal tab title with the time Claude last replied.
#
# Runs after every assistant turn, so the tab reads e.g. "14:32 · Invoice export"
# and the timestamp is the moment of the last response.
#
# Label resolution, first hit wins:
#   1. <state>/<WARP_TERMINAL_SESSION_UUID>       — pinned with `tabname`
#   2. <state>/<WARP_TERMINAL_SESSION_UUID>.auto  — derived from prompt + branch
#   3. <state>/default                            — global fallback file
#   4. $CLAUDE_PLUGIN_OPTION_DEFAULT_LABEL        — plugin configuration
#   5. basename of the project directory          — original behaviour
#
# <state> is ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/warp-tab-name, the same path the
# `tabname` shell function writes to. Both sides have to agree on it, so neither
# may hardcode $HOME.
#
# Warp's own tab rename (right-click → rename) takes precedence over OSC 0 and
# would hide whatever we emit, so the label lives in a file instead.
#
# Delivery: Claude Code >= 2.1.141 accepts a `terminalSequence` field on hook output
# and writes the escape sequence to the terminal itself. Older versions reject unknown
# fields on Stop hooks, so there we write to the controlling tty instead.
set -u

# The headless Claude that warp-tab-autoname.sh spawns to name the tab runs this
# hook when it finishes, from its own working directory. Left alone it would
# stamp the tab with that directory's name, undoing the rename it was spawned to
# perform.
[ "${WARP_TAB_CLOCK_CHILD:-}" = "1" ] && exit 0

TERMINAL_SEQUENCE_MIN_VERSION="2.1.141"
NAME_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/warp-tab-name"

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
[ -n "$base" ] || base="${CLAUDE_PLUGIN_OPTION_DEFAULT_LABEL:-}"
[ -n "$base" ] || base="$(basename "${CLAUDE_PROJECT_DIR:-$PWD}")"

# The title is spliced into a JSON string by hand, so drop the characters that
# would need escaping: quote, backslash and control characters. A tab in a
# hand-written name file is the realistic one, and a raw tab inside a JSON string
# invalidates the whole hook output.
base="${base//\"/}"
base="${base//\\/}"
base="${base//[[:cntrl:]]/}"
title="$(date +%H:%M) · ${base}"

raw="${CLAUDE_CODE_VERSION:-}"
ver="$(printf '%s' "$raw" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

emit_json() { printf '{"terminalSequence":"\\u001b]0;%s\\u0007"}\n' "$title"; }

# Attempt the write and report whether it landed. Testing `-w /dev/tty` first
# would report success for a tty that is not the Warp tab, and the JSON fallback
# below would then never run — the title would silently stop updating.
#
# 2>/dev/null comes first on purpose: redirections are applied left to right, so
# stderr has to be closed off before the /dev/tty one can fail and have the shell
# announce it.
emit_tty() { printf '\033]0;%s\007' "$title" 2>/dev/null > /dev/tty; }

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
