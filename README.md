# warp-claude-tab-clock

Puts a live clock in your Warp tab title while you work in Claude Code.

```
00:32 · test opcji
```

The time is the moment Claude last replied, so a glance at the tab bar tells you
how stale each session is. The label part is either a name you pin yourself or
one derived automatically from the first prompt of the session.

## Requirements

- [Warp](https://warp.dev)
- [Claude Code](https://claude.com/claude-code) **2.1.141 or newer** — older
  versions reject the `terminalSequence` hook output this relies on
- `python3` (ships with macOS) — used only by the installer
- `jq` — needed by the auto-naming hook (`brew install jq`)
- zsh (Warp's default shell on macOS)

## Install

```bash
git clone https://github.com/<you>/warp-claude-tab-clock.git
cd warp-claude-tab-clock
./install.sh
```

The installer is idempotent and backs up every file it touches
(`*.bak-warp-tab-clock`). It will not disturb hooks you already have.

Then two one-off steps:

1. **Clear any manual tab name in Warp.** Right-click the tab → rename → empty
   the field. A manually set name overrides the escape sequence and hides the
   clock completely. This is the single most common reason "nothing happens".
2. **Open a new Warp tab** so `WARP_DISABLE_AUTO_TITLE` is picked up, then run
   `claude` there.

## Usage

The label is resolved on every reply, first match wins:

| Priority | Source | Set by |
|---|---|---|
| 1 | `~/.claude/warp-tab-name/<tab-uuid>` | `tabname "My label"` |
| 2 | `~/.claude/warp-tab-name/<tab-uuid>.auto` | first prompt of the session |
| 3 | `~/.claude/warp-tab-name/default` | you, for a global fallback |
| 4 | project directory name | nothing — this is the fallback |

Pin a name for the current tab:

```bash
tabname "Invoice export"     # -> "00:32 · Invoice export"
tabname                      # clear, fall back to auto-naming
```

Set a fallback for every tab that has no name of its own:

```bash
echo "ACME" > ~/.claude/warp-tab-name/default
```

`tabname` is a zsh function, so it only exists in tabs opened after install. To
rename the tab of a session that is already running, write the file directly:

```bash
echo "New label" > ~/.claude/warp-tab-name/$WARP_TERMINAL_SESSION_UUID
```

### Auto-naming

A `UserPromptSubmit` hook takes the **first prompt of each session**, collapses
it to one line and truncates it to 28 characters. Later prompts in the same
session do not rename the tab — otherwise the label would flicker on every
message. Starting a new Claude session in the same tab does rename it. Prompts
beginning with `/` are skipped, because `/tldr` describes a tab poorly.

## How it works

Two Claude Code hooks, no daemon and no polling:

- **`Stop` → `warp-tab-time.sh`** runs after every assistant turn, resolves the
  label, and emits `OSC 0` (`ESC ] 0 ; <title> BEL`).
- **`UserPromptSubmit` → `warp-tab-autoname.sh`** records a label derived from
  the session's first prompt.

Claude Code cannot write to `/dev/tty` from a hook subprocess, so the escape
sequence is returned as JSON instead:

```json
{"terminalSequence":"]0;00:32 · test opcji"}
```

Claude Code validates it against an allowlist (`OSC 0/1/2/9/99/777` plus `BEL`)
and writes it to the terminal itself. Every hook's sequence is emitted
separately, so this coexists with other hooks — including Warp's own
`claude-code-warp` plugin, which sends `OSC 777` notifications on the same
event.

Two settings keep other parties from overwriting the title:

- `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1` in `settings.json` — stops Claude Code
  from setting its own title.
- `WARP_DISABLE_AUTO_TITLE=true` in `.zshrc` — stops the `precmd`/`preexec`
  hooks Warp injects into zsh from resetting the title to the working directory
  on every prompt. This is Warp's own documented escape hatch for exactly this
  problem.

## Limitations

- **Warp's manual tab rename wins.** If you rename a tab through Warp's UI, that
  name is displayed and nothing this tool emits is visible. The live value is
  also unreadable from outside — Warp persists it to its SQLite database lazily,
  so what is on disk lags behind what is on screen. Renaming a tab
  programmatically is not possible either: Warp's action API does expose
  `tab.rename`, but the local-control server that would accept it is disabled
  and has no public setting to turn it on.
- **Tab colors are not configurable from here.** Warp stores a tab color as a
  closed enum (`Unassigned | Color(<name>)`), so only its named colors exist —
  no custom hex, from any channel.
- **Warp's directory-based tab naming is off** once `WARP_DISABLE_AUTO_TITLE` is
  set. That is the trade: you get your own title, you lose the automatic one.
  It applies to every tab, not just Claude Code sessions.
- macOS/zsh only as written. The hooks themselves are portable; the installer's
  shell wiring is not.

## Troubleshooting

**Title never changes.** Almost always a manual tab name. Right-click the tab →
rename → clear it.

**Title flashes and reverts to the directory.** `WARP_DISABLE_AUTO_TITLE` is not
set in that shell. It only applies to tabs opened after install.

**Auto-naming does nothing.** Check `jq` is installed. Without it the hook exits
silently and the label falls back to the project directory name.

**Check what the hook would emit** — this prints the JSON without touching the
terminal:

```bash
~/.claude/hooks/warp-tab-time.sh
```

**Confirm Warp honours the sequence at all** — run this in a plain Warp tab, not
through Claude Code (Claude Code captures stdout, so the sequence never reaches
the terminal):

```bash
printf '\033]0;ZZZ-TEST\007'
```

If the tab does not read `ZZZ-TEST`, the problem is Warp's configuration, not
this tool.

## Uninstall

```bash
./uninstall.sh
```

Removes the hook scripts, its entries from `settings.json`, the `.zshrc` block
and the saved tab names. Open a new tab afterwards to get Warp's directory-based
names back.

## License

MIT
