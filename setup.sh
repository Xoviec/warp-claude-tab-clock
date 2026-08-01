#!/usr/bin/env bash
# Shell setup for warp-tab-clock.
#
# The hooks themselves come from the Claude Code plugin; this script only adds
# the shell-side block that the plugin cannot install for itself:
#
#   * WARP_DISABLE_AUTO_TITLE      — stop Warp's precmd/preexec hooks from
#                                    resetting the title on every prompt
#   * CLAUDE_CODE_DISABLE_TERMINAL_TITLE — stop Claude Code setting its own title
#   * tabname()                    — pin a label for the current tab
#
# Idempotent: safe to run repeatedly.
set -euo pipefail

ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
NAME_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/warp-tab-name"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*"; }

command -v jq >/dev/null 2>&1 || warn "jq not found — auto-naming will no-op until you install it (brew install jq)"

if [ "${TERM_PROGRAM:-}" != "WarpTerminal" ]; then
    warn "Not running inside Warp. Installing anyway; the hooks emit a standard OSC 0 title."
fi

info "Configuring $ZSHRC"
# Also matches the v1 marker so an upgrade doesn't append a second block.
if grep -qE '^# >>> warp-(claude-)?tab-clock >>>$' "$ZSHRC" 2>/dev/null; then
    echo "    .zshrc already configured"
else
    [ -f "$ZSHRC" ] && cp "$ZSHRC" "$ZSHRC.bak-warp-tab-clock"
    cat >> "$ZSHRC" <<'ZBLOCK'

# >>> warp-tab-clock >>>
# Stop Warp's precmd/preexec hooks from overwriting the tab title.
export WARP_DISABLE_AUTO_TITLE=true
# Stop Claude Code from setting a title of its own, which would fight the hook.
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1

# tabname "My label"  -> pin a label for this Warp tab
# tabname             -> clear it and fall back to auto-naming
tabname() {
  local dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/warp-tab-name"
  local f="$dir/${WARP_TERMINAL_SESSION_UUID:-default}"
  mkdir -p "$dir"
  if [ $# -eq 0 ]; then
    rm -f "$f" && print -r -- "tabname: cleared"
  else
    print -r -- "$*" > "$f" && print -r -- "tabname: $*"
  fi
}
# <<< warp-tab-clock <<<
ZBLOCK
    echo "    .zshrc updated"
fi

mkdir -p "$NAME_DIR"

cat <<'DONE'

Shell configured. Now install the plugin, from inside Claude Code:

  /plugin marketplace add Xoviec/warp-claude-tab-clock
  /plugin install warp-tab-clock@xoviec

Then two one-off steps:

  1. Clear any MANUAL tab name in Warp.
     Right-click the tab -> rename -> empty the field.
     A manual name overrides the escape sequence and hides the clock.

  2. Open a NEW Warp tab so the exports above are picked up,
     then run `claude` there.

The tab title becomes "HH:MM · <label>" and refreshes after every reply.

DONE
