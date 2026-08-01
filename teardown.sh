#!/usr/bin/env bash
# Reverses setup.sh, and cleans up a v1 install that wired the hooks into
# settings.json directly. Leaves your other hooks and settings alone.
#
# Uninstall the plugin itself from inside Claude Code:
#   /plugin uninstall warp-tab-clock@xoviec
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"
NAME_DIR="$CLAUDE_DIR/warp-tab-name"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# --- v1 leftovers -----------------------------------------------------------
if [ -f "$HOOKS_DIR/warp-tab-time.sh" ] || [ -f "$HOOKS_DIR/warp-tab-autoname.sh" ]; then
    info "Removing v1 hook scripts from $HOOKS_DIR"
    rm -f "$HOOKS_DIR/warp-tab-time.sh" "$HOOKS_DIR/warp-tab-autoname.sh"
fi

if [ -f "$SETTINGS" ] && grep -q 'warp-tab-\(time\|autoname\)\.sh' "$SETTINGS" 2>/dev/null; then
    if command -v python3 >/dev/null 2>&1; then
        info "Cleaning v1 entries from $SETTINGS"
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
removed_ours = False
hooks = data.get("hooks", {})
for event in ("Stop", "UserPromptSubmit"):
    entries = hooks.get(event)
    if not entries:
        continue
    kept = []
    for entry in entries:
        before = entry.get("hooks", [])
        after = [h for h in before if h.get("command") not in targets]
        if len(after) != len(before):
            removed_ours = True
        entry["hooks"] = after
        if after:
            kept.append(entry)
    if kept:
        hooks[event] = kept
    else:
        hooks.pop(event, None)
if not hooks:
    data.pop("hooks", None)

# Only drop the env var if this really was our install — otherwise we would be
# deleting a setting the user made themselves.
if removed_ours:
    env = data.get("env", {})
    env.pop("CLAUDE_CODE_DISABLE_TERMINAL_TITLE", None)
    if not env:
        data.pop("env", None)

with open(path, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
print("    done" if removed_ours else "    nothing of ours found, left untouched")
PY
    else
        info "python3 not found — remove the warp-tab-*.sh hook entries from $SETTINGS by hand"
    fi
fi

# --- shell block ------------------------------------------------------------
if [ -f "$ZSHRC" ] && grep -qE '^# >>> warp-(claude-)?tab-clock >>>$' "$ZSHRC"; then
    info "Cleaning $ZSHRC"
    cp "$ZSHRC" "$ZSHRC.bak-warp-tab-clock-uninstall"
    awk '
      /^# >>> warp-(claude-)?tab-clock >>>$/ { skip = 1 }
      !skip { print }
      /^# <<< warp-(claude-)?tab-clock <<<$/ { skip = 0 }
    ' "$ZSHRC.bak-warp-tab-clock-uninstall" > "$ZSHRC"
fi

info "Removing saved tab names ($NAME_DIR)"
rm -rf "$NAME_DIR"

cat <<'DONE'

Shell configuration removed. If the plugin is still installed, remove it too:

  /plugin uninstall warp-tab-clock@xoviec

Open a new Warp tab afterwards to drop WARP_DISABLE_AUTO_TITLE
and get Warp's directory-based tab names back.

DONE
