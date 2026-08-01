#!/bin/bash
# UserPromptSubmit hook — derive a tab label from the first prompt of a session.
#
# Writes <state>/<WARP_TERMINAL_SESSION_UUID>.auto containing:
#   <session_id>\t<name>
#
# where <state> is ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/warp-tab-name.
#
# The session id is stored alongside the name so the name stays stable for the
# whole session, but a new Claude session in the same Warp tab renames it.
# An explicit name (set via `tabname` or written directly) always wins — that
# file is checked first by warp-tab-time.sh.
#
# Privacy: the label ends up in the tab title, which is visible in screenshots,
# screen shares and Warp's own history database. Turn it off with the plugin's
# "Derive labels from the first prompt" option or WARP_TAB_CLOCK_NO_AUTONAME=1.
#
# Must print nothing: stdout from a UserPromptSubmit hook is injected as context.
set -u

NAME_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/warp-tab-name"
MAX_LEN=28

[ "${WARP_TAB_CLOCK_NO_AUTONAME:-}" = "1" ] && exit 0
[ "${CLAUDE_PLUGIN_OPTION_AUTONAME:-true}" = "false" ] && exit 0

uuid="${WARP_TERMINAL_SESSION_UUID:-default}"
target="$NAME_DIR/$uuid.auto"

input="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

# One jq pass produces the whole "<session_id>\t<name>" line. jq does the
# truncation because it counts characters, not bytes: bash's ${name:0:N} falls
# back to bytes under a non-UTF-8 locale and would cut a multibyte character in
# half, leaving invalid UTF-8 in the title and in the emitting hook's JSON.
# Slash commands are skipped — "/tldr" describes a tab poorly.
line="$(printf '%s' "$input" | jq -r --argjson n "$MAX_LEN" '
    def collapse: gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "");
    (.session_id // "") as $sid
    | (.prompt // "") as $raw
    | if $sid == "" or $raw == "" or ($raw | startswith("/")) then empty
      else
        ($raw | split("\n")[0] | collapse) as $name
        | if $name == "" then empty
          else $sid + "\t" + (if ($name | length) > $n then $name[0:$n] + "…" else $name end)
          end
      end' 2>/dev/null)"
[ -n "$line" ] || exit 0

# Keep the name from the session's first prompt; later prompts don't rename,
# otherwise the label would flicker on every message.
if [ -f "$target" ]; then
    IFS=$'\t' read -r prev_session _ < "$target" || true
    [ "${prev_session:-}" = "${line%%$'\t'*}" ] && exit 0
fi

mkdir -p "$NAME_DIR" || exit 0
printf '%s\n' "$line" > "$target" 2>/dev/null
exit 0
