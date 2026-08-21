# Changelog

Versions are the plugin's, from `.claude-plugin/plugin.json`.

## 1.4.0 — 2026-08-03

- The title leads with a state, so the tab says whose turn it is: 🟡 while a turn
  runs, 🔴 when Claude wants a permission decision, 🟢 once the answer landed.
  Every emission restamps the clock, so the time is when the state last changed
  rather than only when Claude last replied.
- `PostToolUse` returns a red tab to 🟡 once a permission is granted, without
  spending an emission on each of the dozens of tool calls in a turn.
- Turn the dot off with the **Colour the tab by what the session is doing**
  option or `WARP_TAB_CLOCK_NO_STATE=1`.

## 1.3.0 — 2026-08-02

- A session opened with a command is named after the command:
  `/review-summary <url>` gives `Review summary`. Arguments never reach the
  title, which keeps URLs and pasted context out of it. Namespaced commands use
  their leaf, and a `#2121` among the arguments is still taken as a ref.
- Commands that only operate Claude Code — `/clear`, `/login`, `/plugin` and
  their like — name nothing and leave the tab as it was.
- Previously any prompt starting with `/` was dropped, which left such sessions
  on the last fallback there is: the project directory name.

## 1.2.0 — 2026-08-02

- The derived label is now a placeholder that a one-shot headless Claude rewrites
  into the actual topic — `Przegląd repo FE` rather than
  `przejrzyj szybko moje repo fe`. It runs detached, so the turn is never held up
  for the call.
- **This sends the first prompt of a session to the API**, once per session, on
  Haiku. Turn it off with the **Let a model name the tab** option or
  `WARP_TAB_CLOCK_NO_LLM_NAME=1`.
- The spawned session cannot disturb the tab it names: it carries a marker that
  stops both hooks inside it, and an empty tab uuid so an older installed copy
  that predates the marker cannot reach the live tab's state file. A failed or
  unauthenticated CLI leaves the placeholder rather than naming the tab after the
  error.

## 1.1.0 — 2026-08-02

- Labels are derived from the work rather than from the prompt verbatim:
  `<kind> <ref>`, as in `Code review #2121` or `Fix #2321`. The kind comes from
  the verbs in the prompt, recognised in English and Polish; the ref from a
  `#number` or an issue key, falling back to one parsed out of the current git
  branch.
- Renaming follows the ref, so follow-ups like "add a test" leave the title
  alone instead of flickering on every message.
- `teardown.sh` also sweeps a v1 install that lives outside `CLAUDE_CONFIG_DIR`.
  It previously reported success while leaving v1 firing on every prompt.

## 1.0.0 — 2026-08-02

- Shipped as a Claude Code plugin: `/plugin marketplace add Xoviec/warp-claude-tab-clock`.
  The hooks no longer have to be wired into `settings.json` by hand — run
  `teardown.sh` once to clear a v1 install.
- Configurable default tab label.

## Before 1.0.0

- First version: a live clock and a label in the Warp tab title, installed by
  script into `~/.claude/settings.json`.
