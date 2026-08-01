#!/usr/bin/env bash
# Removes everything install.sh added. Leaves your other hooks and settings alone.
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

info "Removing hook scripts"
rm -f "$HOOKS_DIR/warp-tab-time.sh" "$HOOKS_DIR/warp-tab-autoname.sh"

if [ -f "$SETTINGS" ] && command -v python3 >/dev/null 2>&1; then
    info "Cleaning $SETTINGS"
    python3 - "$SETTINGS" <<'PY'
import json, shutil, sys

path = sys.argv[1]
shutil.copy2(path, path + ".bak-warp-tab-clock-uninstall")
with open(path) as fh:
    data = json.load(fh)

targets = {
    "$HOME/.claude/hooks/warp-tab-time.sh",
    "$HOME/.claude/hooks/warp-tab-autoname.sh",
}
hooks = data.get("hooks", {})
for event in ("Stop", "UserPromptSubmit"):
    entries = hooks.get(event)
    if not entries:
        continue
    kept = []
    for entry in entries:
        entry["hooks"] = [h for h in entry.get("hooks", []) if h.get("command") not in targets]
        if entry["hooks"]:
            kept.append(entry)
    if kept:
        hooks[event] = kept
    else:
        hooks.pop(event, None)
if not hooks:
    data.pop("hooks", None)

env = data.get("env", {})
env.pop("CLAUDE_CODE_DISABLE_TERMINAL_TITLE", None)
if not env:
    data.pop("env", None)

with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
print("    done")
PY
fi

if [ -f "$ZSHRC" ] && grep -qF ">>> warp-claude-tab-clock >>>" "$ZSHRC"; then
    info "Cleaning $ZSHRC"
    cp "$ZSHRC" "$ZSHRC.bak-warp-tab-clock-uninstall"
    awk '
      /^# >>> warp-claude-tab-clock >>>$/ { skip = 1 }
      !skip { print }
      /^# <<< warp-claude-tab-clock <<<$/ { skip = 0 }
    ' "$ZSHRC.bak-warp-tab-clock-uninstall" > "$ZSHRC"
fi

info "Removing saved tab names"
rm -rf "$HOME/.claude/warp-tab-name"

cat <<'DONE'

Uninstalled. Open a new Warp tab to drop WARP_DISABLE_AUTO_TITLE
and get Warp's directory-based tab names back.

DONE
