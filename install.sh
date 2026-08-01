#!/usr/bin/env bash
# Installer for warp-claude-tab-clock.
# Idempotent: safe to run repeatedly, existing hooks and settings are preserved.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m x\033[0m %s\n' "$*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || die "python3 is required (used to merge settings.json)"
command -v jq >/dev/null 2>&1 || warn "jq not found — the auto-naming hook will no-op until you install it (brew install jq)"
[ -d "$CLAUDE_DIR" ] || die "$CLAUDE_DIR not found. Install and start Claude Code once, then re-run."

if [ "${TERM_PROGRAM:-}" != "WarpTerminal" ]; then
    warn "Not running inside Warp. Installing anyway; the hooks emit a standard OSC 0 title."
fi

info "Installing hooks into $HOOKS_DIR"
mkdir -p "$HOOKS_DIR"
install -m 755 "$REPO_DIR/hooks/warp-tab-time.sh"     "$HOOKS_DIR/warp-tab-time.sh"
install -m 755 "$REPO_DIR/hooks/warp-tab-autoname.sh" "$HOOKS_DIR/warp-tab-autoname.sh"

info "Merging Claude Code settings ($SETTINGS)"
python3 - "$SETTINGS" <<'PY'
import json, os, shutil, sys

path = sys.argv[1]
data = {}
if os.path.exists(path):
    shutil.copy2(path, path + ".bak-warp-tab-clock")
    with open(path) as fh:
        try:
            data = json.load(fh)
        except json.JSONDecodeError as exc:
            sys.exit(f"settings.json is not valid JSON: {exc}")

hooks = data.setdefault("hooks", {})

def ensure(event, command):
    """Append a hook entry unless that exact command is already registered."""
    entries = hooks.setdefault(event, [])
    for entry in entries:
        for hook in entry.get("hooks", []):
            if hook.get("command") == command:
                return False
    entries.append({"hooks": [{"type": "command", "command": command}]})
    return True

changed = False
changed |= ensure("Stop", "$HOME/.claude/hooks/warp-tab-time.sh")
changed |= ensure("UserPromptSubmit", "$HOME/.claude/hooks/warp-tab-autoname.sh")

# Claude Code sets its own terminal title; that would fight the Stop hook.
env = data.setdefault("env", {})
if env.get("CLAUDE_CODE_DISABLE_TERMINAL_TITLE") != "1":
    env["CLAUDE_CODE_DISABLE_TERMINAL_TITLE"] = "1"
    changed = True

with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")

print("    settings.json updated" if changed else "    settings.json already configured")
PY

info "Configuring $ZSHRC"
if grep -qF ">>> warp-claude-tab-clock >>>" "$ZSHRC" 2>/dev/null; then
    echo "    .zshrc already configured"
else
    [ -f "$ZSHRC" ] && cp "$ZSHRC" "$ZSHRC.bak-warp-tab-clock"
    cat >> "$ZSHRC" <<'ZBLOCK'

# >>> warp-claude-tab-clock >>>
# Stop Warp's precmd/preexec hooks from overwriting the tab title.
export WARP_DISABLE_AUTO_TITLE=true

# tabname "My label"  -> pin a base name for this Warp tab
# tabname             -> clear it and fall back to auto-naming
tabname() {
  local dir="$HOME/.claude/warp-tab-name"
  local f="$dir/${WARP_TERMINAL_SESSION_UUID:-default}"
  mkdir -p "$dir"
  if [ $# -eq 0 ]; then
    rm -f "$f" && print -r -- "tabname: cleared"
  else
    print -r -- "$*" > "$f" && print -r -- "tabname: $*"
  fi
}
# <<< warp-claude-tab-clock <<<
ZBLOCK
    echo "    .zshrc updated"
fi

mkdir -p "$HOME/.claude/warp-tab-name"

cat <<'DONE'

Installed.

Two things left, both one-off:

  1. Clear any MANUAL tab name in Warp.
     Right-click the tab -> rename -> empty the field.
     A manual name overrides the escape sequence and hides the clock.

  2. Open a NEW Warp tab so WARP_DISABLE_AUTO_TITLE is picked up,
     then run `claude` there.

The tab title becomes "HH:MM · <name>" and refreshes after every reply.

DONE
