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
# the prompt stands on its own.
#
# That last case is the common one outside ticket-driven work, and a raw prompt
# is a poor tab title — "przejrzyj szybko moje repo fe" says how it was asked,
# not what it is about. So the regex label is only the placeholder: a one-shot
# headless Claude then rewrites it into an actual topic ("Przegląd repo FE"), in
# the background, and the tab settles a few seconds into the first answer. See
# the summariser at the foot of this file.
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
LLM_MODEL="${WARP_TAB_CLOCK_LLM_MODEL:-haiku}"
LLM_TIMEOUT="${WARP_TAB_CLOCK_LLM_TIMEOUT:-25}"

# The summariser spawns a headless Claude, and that Claude runs this very hook —
# and the Stop hook with it. Unguarded, the first forks without end and the
# second stamps the tab with the child's own directory. Both scripts bail on
# this marker, which the spawn sets on the child's environment.
[ "${WARP_TAB_CLOCK_CHILD:-}" = "1" ] && exit 0
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
      # Last of the kinds: "sprawdź czy X się nie sypie" is a Fix, and only a
      # prompt that matched nothing above is plain analysis.
      elif test("\\banaly[sz]|\\binspect\\b|przeanalizuj|przejrz(yj|e[ćc])|zbadaj|sprawd[źz]"; "i") then "Analysis"
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
            | $sid + "\t" + $name + "\n" + $ref + "\n" + $text
          end
      end' 2>/dev/null)"
[ -n "$out" ] || exit 0

# Three lines out, two lines stored: the collapsed prompt is what the summariser
# below is handed, and it has no business in the file the Stop hook reads.
line=""; ref=""; text=""
{ IFS= read -r line; IFS= read -r ref; IFS= read -r text; } <<< "$out"
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

# --- the topic, from the model ------------------------------------------------
#
# Everything above is a placeholder built out of the prompt's own words. This
# turns it into what the session is actually about.
#
# It runs only where a label was just written — once per session, and again on a
# change of ticket — so a session costs one small model call, not one per turn.
# It runs detached because the call takes a few seconds and a UserPromptSubmit
# hook holds the turn for as long as it lasts; the tab renames itself partway
# through the first answer instead.
[ "${WARP_TAB_CLOCK_NO_LLM_NAME:-}" = "1" ] && exit 0
[ "${CLAUDE_PLUGIN_OPTION_LLM_NAME:-true}" = "false" ] && exit 0
[ -n "$text" ] || exit 0
command -v claude >/dev/null 2>&1 || exit 0

(
    # A neutral working directory keeps the child off the project's own settings
    # and CLAUDE.md — cheaper, and one less way for a project hook to recurse.
    cd "$NAME_DIR" 2>/dev/null || exit 0

    answer=""
    tmp="$target.llm.$$"
    # The state directory is not swept by anything, so a subshell killed before
    # its own cleanup would leave this behind for good.
    trap 'rm -f "$tmp" 2>/dev/null' EXIT INT TERM

    # WARP_TAB_CLOCK_CHILD stops this hook in the child. Clearing the tab uuid
    # is the second line of defence, for the case that guard cannot cover: an
    # older copy of this script still installed as the plugin, which has never
    # heard of the marker. Without a uuid it resolves the state file to
    # "default.auto", which nothing reads, instead of the live tab's.
    WARP_TAB_CLOCK_CHILD=1 WARP_TERMINAL_SESSION_UUID= claude -p --model "$LLM_MODEL" \
        "Name the terminal tab for this coding session. Reply with ONLY the topic: 2-4 words, at most $MAX_LEN characters, in the language the request is written in, no quotes and no trailing period. Request: $text" \
        > "$tmp" 2>/dev/null &
    child=$!
    ( sleep "$LLM_TIMEOUT"; kill "$child" 2>/dev/null ) &
    watchdog=$!
    wait "$child" 2>/dev/null; status=$?
    kill "$watchdog" 2>/dev/null

    answer="$(cat "$tmp" 2>/dev/null)"
    rm -f "$tmp" 2>/dev/null

    # The CLI reports "Not logged in", and its like, on stdout and leaves,
    # so silencing stderr is not enough to keep an error out of the tab title.
    # A non-zero status also covers the watchdog's kill.
    [ "$status" -eq 0 ] || exit 0

    # jq again for the truncation, for the same reason as above: it counts
    # characters. A refusal or an apology arrives as several lines, so only the
    # first line with anything on it is taken, and stray quoting is dropped.
    topic="$(printf '%s' "$answer" | jq -Rrs --argjson n "$MAX_LEN" '
        split("\n") | map(select(test("[^[:space:]]"))) | (.[0] // "")
        | gsub("[\"“”`]"; "")
        | gsub("[[:space:]]+"; " ") | sub("^ "; "") | sub(" $"; "") | sub("[.]$"; "")
        | if length > $n then .[0:$n] + "…" else . end' 2>/dev/null)"
    [ -n "$topic" ] || exit 0

    # Several seconds have passed, and the tab may have moved on to another
    # session in the meantime. Only the session this label was derived from gets
    # to be renamed by it.
    current=""
    [ -f "$target" ] && { IFS= read -r current < "$target" || true; }
    [ "${current%%$'\t'*}" = "$sid" ] || exit 0

    printf '%s\t%s\n%s\n' "$sid" "$topic" "$ref" > "$target" 2>/dev/null
) >/dev/null 2>&1 &
disown 2>/dev/null

exit 0
