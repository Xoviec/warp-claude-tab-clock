#!/usr/bin/env bash
# Reverses setup.sh, and cleans up a v1 install that wired the hooks into
# settings.json directly. Leaves your other hooks and settings alone.
#
# Uninstall the plugin itself from inside Claude Code:
#   /plugin uninstall warp-tab-clock@xoviec
set -euo pipefail

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
ZSHRC="${ZDOTDIR:-$HOME}/.zshrc"

# v1 installed into $HOME/.claude and wrote that path into settings.json
# literally, whatever CLAUDE_CONFIG_DIR happens to say today. Sweeping only the
# configured directory would report success while leaving v1 live, so both are
# cleaned when they differ.
CLAUDE_DIRS=("$CLAUDE_DIR")
if [ "$CLAUDE_DIR" != "$HOME/.claude" ]; then
    CLAUDE_DIRS+=("$HOME/.claude")
fi

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# --- v1 leftovers -----------------------------------------------------------
for dir in "${CLAUDE_DIRS[@]}"; do
HOOKS_DIR="$dir/hooks"
SETTINGS="$dir/settings.json"

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

# Matched by script name rather than by full path: the entry holds whatever
# $HOME expanded to on the machine that installed it.
targets = ("warp-tab-time.sh", "warp-tab-autoname.sh")
def ours(hook):
    cmd = hook.get("command") or ""
    return any(name in cmd for name in targets)

removed_ours = False
hooks = data.get("hooks", {})
for event in ("Stop", "UserPromptSubmit"):
    entries = hooks.get(event)
    if not entries:
        continue
    kept = []
    for entry in entries:
        before = entry.get("hooks", [])
        after = [h for h in before if not ours(h)]
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
done

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

for dir in "${CLAUDE_DIRS[@]}"; do
    [ -d "$dir/warp-tab-name" ] || continue
    info "Removing saved tab names ($dir/warp-tab-name)"
    rm -rf "$dir/warp-tab-name"
done

cat <<'DONE'

Shell configuration removed. If the plugin is still installed, remove it too:

  /plugin uninstall warp-tab-clock@xoviec

Open a new Warp tab afterwards to drop WARP_DISABLE_AUTO_TITLE
and get Warp's directory-based tab names back.

DONE
