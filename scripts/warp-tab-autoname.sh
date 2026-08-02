#!/bin/bash
# UserPromptSubmit hook — derive a tab label from what the session is about.
#
# Writes <state>/<WARP_TERMINAL_SESSION_UUID>.auto containing:
#   <session_id>\t<name>
#   <ref>
#
# where <state> is ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/warp-tab-name. Only the
# first line is part of the contract with warp-tab-time.sh, which reads a single
# line; the second holds the issue reference the label was derived from, so a
# later prompt can tell "same ticket" from "moved on".
#
# The label is "<kind> <ref>" — "Code review #2121", "Fix #2321" — where the kind
# comes from the verbs in the prompt and the ref from a #number or issue key in
# the prompt, falling back to one parsed out of the current git branch. Without a
# ref the kind still prefixes the prompt ("Feat: dodaj dark mode"); without either
# the prompt stands on its own, which is the original behaviour.
#
# Renaming rule: the label is set once per Claude session, then replaced only when
# the ref changes — a new ticket, or a branch switch. Prompts that carry no ref
# leave the title alone, so it does not flicker on follow-ups like "add a test".
#
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

# symbolic-ref only reads .git/HEAD, so this stays cheap enough for every prompt.
# It is also the form that survives a branch with no commits yet, where
# `rev-parse --abbrev-ref HEAD` fails outright. Outside a repository, on a
# detached HEAD, or without git at all, it yields "".
branch=""
if command -v git >/dev/null 2>&1; then
    branch="$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" symbolic-ref --short -q HEAD 2>/dev/null)" || branch=""
fi

# One jq pass produces "<session_id>\t<name>" and the ref on a second line. jq
# does the truncation because it counts characters, not bytes: bash's
# ${name:0:N} falls back to bytes under a non-UTF-8 locale and would cut a
# multibyte character in half, leaving invalid UTF-8 in the title and in the
# emitting hook's JSON. Slash commands are skipped — "/tldr" describes a tab
# poorly.
out="$(printf '%s' "$input" | jq -r --argjson n "$MAX_LEN" --arg branch "$branch" '
    def collapse: gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "");

    # First match wins, so the specific kinds are tested before the catch-all
    # "Feat" — "zrób code review" is a review, not a feature.
    def kind_of:
      if test("code ?review|\\breview\\b|przegl[ąa]d|zrecenzuj"; "i") then "Code review"
      elif test("\\bfix(es|ed|ing)?\\b|\\bbugs?\\b|\\bhotfix\\b|napraw|popraw|b[łl][ąa]d|debuguj"; "i") then "Fix"
      elif test("\\brefactor(ing)?\\b|refaktor|przepisz|uporz[ąa]dkuj|posprz[ąa]taj"; "i") then "Refactor"
      elif test("\\btests?(ing)?\\b|\\btesty\\b|przetestuj|pokrycie"; "i") then "Test"
      elif test("\\bdocs?\\b|\\breadme\\b|dokumentacj|udokumentuj|opisz"; "i") then "Docs"
      elif test("\\bdeploy(ment)?\\b|\\brelease\\b|wdr[oó][żz]|wydanie|opublikuj"; "i") then "Release"
      elif test("\\badds?\\b|\\bimplement(s|ed|ing)?\\b|\\bfeat(ure)?\\b|dodaj|zaimplementuj|stw[oó]rz|napisz|zr[oó]b"; "i") then "Feat"
      else "" end;

    # "#2121" first, then an uppercase issue key like PROJ-123. Requiring digits
    # after the dash keeps "utf-8" and "claude-5" out.
    def ref_of:
      ([scan("#[0-9]+")] | .[0] // "") as $hash
      | if $hash != "" then $hash
        else ([scan("\\b[A-Z][A-Z0-9]{1,9}-[0-9]+\\b")] | .[0] // "") end;

    # Branch names are lowercase by convention, so the key is matched case
    # insensitively and upcased. A bare run of two or more digits covers
    # "fix/2321-crash"; a single digit is left alone, or "feat/v2-x" would
    # turn into "#2".
    def branch_ref:
      ([scan("\\b[A-Za-z][A-Za-z0-9]{1,9}-[0-9]+\\b")] | .[0] // "") as $key
      | if $key != "" then ($key | ascii_upcase)
        else ([scan("[0-9]{2,}")] | .[0] // "") | if . == "" then "" else "#" + . end
        end;

    (.session_id // "") as $sid
    | (.prompt // "") as $raw
    | if $sid == "" or $raw == "" or ($raw | startswith("/")) then empty
      else
        ($raw | split("\n")[0] | collapse) as $text
        | if $text == "" then empty
          else
            ($text | kind_of) as $kind
            | ($text | ref_of) as $own
            | (if $own != "" then $own else ($branch | branch_ref) end) as $ref
            | (if $kind != "" and $ref != "" then $kind + " " + $ref
               # Prefixing a prompt that already says "fix" with "Fix:" reads as
               # a stutter, so there the prompt speaks for itself.
               elif $kind != "" then
                 (if ($text | test($kind; "i")) then $text else $kind + ": " + $text end)
               # A ref the prompt already spells out needs no prefix. One taken
               # from the branch goes first: truncation eats the tail, and the
               # number is the part worth keeping.
               elif $ref != "" and $own == "" then $ref + " " + $text
               else $text end) as $label
            | (if ($label | length) > $n then $label[0:$n] + "…" else $label end) as $name
            | $sid + "\t" + $name + "\n" + $ref
          end
      end' 2>/dev/null)"
[ -n "$out" ] || exit 0

line="${out%%$'\n'*}"
ref="${out#*$'\n'}"
[ "$ref" = "$out" ] && ref=""
sid="${line%%$'\t'*}"

# Within one Claude session the label only follows a change of ticket. A new
# session in the same tab always renames.
if [ -f "$target" ]; then
    prev_line=""; prev_ref=""
    { IFS= read -r prev_line; IFS= read -r prev_ref; } < "$target" || true
    if [ "${prev_line%%$'\t'*}" = "$sid" ]; then
        [ -n "$ref" ] && [ "$ref" != "$prev_ref" ] || exit 0
    fi
fi

mkdir -p "$NAME_DIR" || exit 0
printf '%s\n%s\n' "$line" "$ref" > "$target" 2>/dev/null
exit 0
