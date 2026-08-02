#!/usr/bin/env bash
# Hook tests. Run from anywhere: ./tests/test-hooks.sh
#
# Each case runs a hook against a throwaway CLAUDE_CONFIG_DIR, so nothing here
# touches your real configuration.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIME_HOOK="$ROOT/scripts/warp-tab-time.sh"
AUTO_HOOK="$ROOT/scripts/warp-tab-autoname.sh"

pass=0; fail=0; skip=0
ok()      { pass=$((pass + 1)); printf '  \033[0;32mok\033[0m   %s\n' "$1"; }
notok()   { fail=$((fail + 1)); printf '  \033[0;31mFAIL\033[0m %s\n' "$1"; printf '       %s\n' "$2"; }
skipped() { skip=$((skip + 1)); printf '  \033[0;33mskip\033[0m %s (%s)\n' "$1" "$2"; }

assert_eq() { # <label> <expected> <actual>
    if [ "$2" = "$3" ]; then ok "$1"; else notok "$1" "expected [$2], got [$3]"; fi
}
assert_contains() { # <label> <needle> <haystack>
    case "$3" in *"$2"*) ok "$1" ;; *) notok "$1" "[$3] does not contain [$2]" ;; esac
}
assert_no_file() { # <label> <path>
    if [ -f "$2" ]; then notok "$1" "$2 was written"; else ok "$1"; fi
}

command -v jq >/dev/null 2>&1 || { echo "jq is required to run the tests"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Isolate every run: fresh config dir, known Warp tab uuid, known project dir.
export CLAUDE_CONFIG_DIR="$TMP/claude"
export WARP_TERMINAL_SESSION_UUID="tab-uuid"
export CLAUDE_PROJECT_DIR="$TMP/my-project"
NAME_DIR="$CLAUDE_CONFIG_DIR/warp-tab-name"
mkdir -p "$NAME_DIR" "$CLAUDE_PROJECT_DIR"

reset_names() { rm -rf "$NAME_DIR"; mkdir -p "$NAME_DIR"; }

# Title as the hook would emit it, with the leading "HH:MM · " stripped.
label_of() { # <json>
    printf '%s' "$1" | jq -r '.terminalSequence' | sed -e 's/^.*]0;[0-9][0-9]:[0-9][0-9] · //' -e 's/$//' | tr -d '\a\033'
}

echo
echo "warp-tab-time.sh — label resolution"

export CLAUDE_CODE_VERSION="2.1.141"   # >= min, so the hook emits JSON, never /dev/tty
unset CLAUDE_PLUGIN_OPTION_DEFAULT_LABEL

reset_names
out="$("$TIME_HOOK")"
assert_eq "falls back to the project directory name" "my-project" "$(label_of "$out")"

reset_names
out="$(CLAUDE_PLUGIN_OPTION_DEFAULT_LABEL="From plugin config" "$TIME_HOOK")"
assert_eq "plugin config beats the project directory" "From plugin config" "$(label_of "$out")"

reset_names
echo "Global fallback" > "$NAME_DIR/default"
out="$(CLAUDE_PLUGIN_OPTION_DEFAULT_LABEL="From plugin config" "$TIME_HOOK")"
assert_eq "default file beats plugin config" "Global fallback" "$(label_of "$out")"

printf 'sess-1\tAuto label\n' > "$NAME_DIR/tab-uuid.auto"
out="$("$TIME_HOOK")"
assert_eq "auto name beats the default file" "Auto label" "$(label_of "$out")"

echo "Pinned label" > "$NAME_DIR/tab-uuid"
out="$("$TIME_HOOK")"
assert_eq "pinned name beats the auto name" "Pinned label" "$(label_of "$out")"

echo
echo "warp-tab-time.sh — output safety"

reset_names
printf 'has\ta tab\n' > "$NAME_DIR/tab-uuid"
out="$("$TIME_HOOK")"
if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    ok "a tab in the label still yields valid JSON"
else
    notok "a tab in the label still yields valid JSON" "invalid JSON: $out"
fi

reset_names
printf 'quote " and backslash \\ here\n' > "$NAME_DIR/tab-uuid"
out="$("$TIME_HOOK")"
if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    assert_eq "quote and backslash are stripped" "quote  and backslash  here" "$(label_of "$out")"
else
    notok "quote and backslash are stripped" "invalid JSON: $out"
fi

reset_names
seq="$("$TIME_HOOK" | jq -r '.terminalSequence')"
assert_contains "emits an OSC 0 sequence" "]0;" "$seq"

if (: > /dev/tty) 2>/dev/null; then
    skipped "old Claude Code writes to the tty, not stdout" "a controlling tty is present"
else
    out="$(CLAUDE_CODE_VERSION=2.1.140 "$TIME_HOOK" 2>/dev/null)"
    assert_eq "old Claude Code writes to the tty, not stdout" "" "$out"
fi

echo
echo "warp-tab-autoname.sh"

run_auto() { # <json payload> — returns hook stdout, which must always be empty
    printf '%s' "$1" | "$AUTO_HOOK"
}
auto_file="$NAME_DIR/tab-uuid.auto"

reset_names
out="$(run_auto '{"session_id":"s1","prompt":"Fix the invoice export"}')"
assert_eq "prints nothing to stdout" "" "$out"
assert_eq "records session id and label" "s1	Fix the invoice export" "$(cat "$auto_file" 2>/dev/null)"

run_auto '{"session_id":"s1","prompt":"and now something else"}' >/dev/null
assert_eq "a later prompt in the same session does not rename" "s1	Fix the invoice export" "$(cat "$auto_file")"

run_auto '{"session_id":"s2","prompt":"A brand new session"}' >/dev/null
assert_eq "a new session does rename" "s2	A brand new session" "$(cat "$auto_file")"

reset_names
run_auto '{"session_id":"s1","prompt":"/tldr"}' >/dev/null
assert_no_file "slash commands are skipped" "$auto_file"

reset_names
run_auto '{"session_id":"s1","prompt":"first line\nsecond line"}' >/dev/null
assert_eq "only the first line is used" "s1	first line" "$(cat "$auto_file")"

reset_names
run_auto '{"session_id":"s1","prompt":"  lots   of \t whitespace  "}' >/dev/null
assert_eq "whitespace is collapsed and trimmed" "s1	lots of whitespace" "$(cat "$auto_file")"

# The regression this guards: bash's ${name:0:28} counts bytes under a non-UTF-8
# locale and cuts a multibyte character in half.
reset_names
LC_ALL=C run_auto '{"session_id":"s1","prompt":"ąęśćżźółń ąęśćżźółń ąęśćżźółń ąęśćżźółń"}' >/dev/null
name="$(cut -f2 "$auto_file")"
if printf '%s' "$name" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
    ok "multibyte label survives LC_ALL=C intact"
else
    notok "multibyte label survives LC_ALL=C intact" "invalid UTF-8: $name"
fi
assert_eq "truncates to 28 characters plus an ellipsis" "29" "$(printf '%s' "$name" | jq -Rr 'length')"

reset_names
WARP_TAB_CLOCK_NO_AUTONAME=1 run_auto '{"session_id":"s1","prompt":"Something private"}' >/dev/null
assert_no_file "WARP_TAB_CLOCK_NO_AUTONAME=1 opts out" "$auto_file"

reset_names
CLAUDE_PLUGIN_OPTION_AUTONAME=false run_auto '{"session_id":"s1","prompt":"Something private"}' >/dev/null
assert_no_file "the autoname plugin option opts out" "$auto_file"

echo
echo "warp-tab-autoname.sh — kind and ref"

label_line() { head -1 "$auto_file" 2>/dev/null | cut -f2- ; }
ref_line()   { sed -n '2p' "$auto_file" 2>/dev/null ; }

reset_names
run_auto '{"session_id":"s1","prompt":"zrób code review #2121"}' >/dev/null
assert_eq "kind plus ref from the prompt" "Code review #2121" "$(label_line)"
assert_eq "the ref is kept on the second line" "#2121" "$(ref_line)"

reset_names
run_auto '{"session_id":"s1","prompt":"review PROJ-123 before merge"}' >/dev/null
assert_eq "an issue key works as a ref" "Code review PROJ-123" "$(label_line)"

reset_names
run_auto '{"session_id":"s1","prompt":"dodaj dark mode"}' >/dev/null
assert_eq "kind prefixes the prompt when there is no ref" "Feat: dodaj dark mode" "$(label_line)"

reset_names
run_auto '{"session_id":"s1","prompt":"Fix the invoice export"}' >/dev/null
assert_eq "a prompt that already names the kind is not prefixed" "Fix the invoice export" "$(label_line)"

reset_names
run_auto '{"session_id":"s1","prompt":"co z #77"}' >/dev/null
assert_eq "a ref the prompt spells out is not repeated" "co z #77" "$(label_line)"

# Renaming follows the ref, not every prompt.
reset_names
run_auto '{"session_id":"s1","prompt":"zrób code review #2121"}' >/dev/null
run_auto '{"session_id":"s1","prompt":"a teraz napraw #2321"}' >/dev/null
assert_eq "a new ref mid-session renames" "Fix #2321" "$(label_line)"

run_auto '{"session_id":"s1","prompt":"dopisz jeszcze test"}' >/dev/null
assert_eq "a prompt without a ref leaves the label alone" "Fix #2321" "$(label_line)"

run_auto '{"session_id":"s1","prompt":"jeszcze raz #2321"}' >/dev/null
assert_eq "the same ref again does not rename" "Fix #2321" "$(label_line)"

echo
echo "warp-tab-autoname.sh — ref from the git branch"

if command -v git >/dev/null 2>&1; then
    REPO="$TMP/repo"
    mkdir -p "$REPO"
    git init -q -b fix/2321-crash "$REPO" 2>/dev/null

    reset_names
    out="$(CLAUDE_PROJECT_DIR="$REPO" run_auto '{"session_id":"s1","prompt":"napraw ten bug"}')"
    assert_eq "the branch supplies the ref the prompt lacks" "Fix #2321" "$(label_line)"

    git -C "$REPO" checkout -q -b feat/insights-flash 2>/dev/null
    reset_names
    CLAUDE_PROJECT_DIR="$REPO" run_auto '{"session_id":"s1","prompt":"dodaj dark mode"}' >/dev/null
    assert_eq "a branch without a number yields no ref" "Feat: dodaj dark mode" "$(label_line)"

    git -C "$REPO" checkout -q -b feat/v2-migration 2>/dev/null
    reset_names
    CLAUDE_PROJECT_DIR="$REPO" run_auto '{"session_id":"s1","prompt":"dodaj dark mode"}' >/dev/null
    assert_eq "a single digit in the branch is not a ref" "Feat: dodaj dark mode" "$(label_line)"

    git -C "$REPO" checkout -q -b bugfix/proj-77-crash 2>/dev/null
    reset_names
    CLAUDE_PROJECT_DIR="$REPO" run_auto '{"session_id":"s1","prompt":"napraw ten bug"}' >/dev/null
    assert_eq "an issue key in the branch is upcased" "Fix PROJ-77" "$(label_line)"

    # Switching branch is a change of subject, even mid-session.
    git -C "$REPO" checkout -q -b fix/2321-crash 2>/dev/null
    CLAUDE_PROJECT_DIR="$REPO" run_auto '{"session_id":"s1","prompt":"napraw ten bug"}' >/dev/null
    assert_eq "a branch switch mid-session renames" "Fix #2321" "$(label_line)"
else
    skipped "ref from the git branch" "git not installed"
fi

reset_names
run_auto '{"session_id":"s1","prompt":"napraw ten bug"}' >/dev/null
assert_eq "outside a repository the prompt still names the tab" "Fix: napraw ten bug" "$(label_line)"

echo
printf '%s passed, %s failed, %s skipped\n' "$pass" "$fail" "$skip"
[ "$fail" -eq 0 ]
