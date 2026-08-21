# Security

## Reporting a vulnerability

Use GitHub's private reporting: **Security → Report a vulnerability** on this
repository. Please do not open a public issue for anything exploitable.

Expect an acknowledgement within a week. This is a spare-time project, so a fix
lands when it lands — if that is not fast enough for you, the whole thing is four
shell scripts and a fork is a reasonable answer.

## Supported versions

Only the latest version. There are no maintenance branches.

## What this plugin can do on your machine

Worth knowing before you install anything that hooks Claude Code:

- **Its scripts run on every prompt, every tool call and every reply.** They are
  Claude Code hooks; that is the mechanism. `scripts/` is 430 lines of shell and
  reading it is the only real assurance.
- **It writes to two places.** One file per Warp tab under
  `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/warp-tab-name`, and — only if you run
  `setup.sh` — a marked block in `~/.zshrc`, backed up first. `teardown.sh`
  removes both.
- **It sends the first prompt of each session to the Anthropic API**, unless you
  turn that off. The tab's topic is written by a model, once per session.
  [Auto-naming](README.md#auto-naming) describes the call and the two ways to
  disable it; [Configuration](README.md#configuration) is the short version.
- **It puts text derived from your prompts into the tab title.** Warp persists
  titles to its own database, and they appear in screenshots and screen shares,
  so a label outlives the session. That can be turned off too.
- **It does not phone anywhere else, read your code, or send anything to a third
  party.** No network calls other than the model call above, and no telemetry.

## Trust boundary worth naming

Hook output reaches your terminal as an escape sequence. Claude Code validates it
against an allowlist (`OSC 0/1/2/9/99/777` plus `BEL`) before writing it, and
this plugin only ever emits `OSC 0`. If you find a way to get anything else past
that from a tab label, that is a vulnerability and worth reporting.
