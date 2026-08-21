# Contributing

Issues and pull requests are welcome. This is a small project — four shell
scripts and two manifests — so there is no process beyond what is below.

## Reporting a problem

Most reports are "the title never changes", and most of those are a manual tab
name in Warp. Please walk the [Troubleshooting](README.md#troubleshooting)
section first: it separates the three ways the title gets overwritten, and the
last two checks there tell you whether the problem is this plugin or Warp's own
configuration.

If it survives that, open an issue with the versions of Claude Code and Warp, and
what the tab title actually read.

## Working on the scripts

```bash
./tests/test-hooks.sh              # hooks, against a throwaway config dir
claude plugin validate . --strict  # manifests
shellcheck scripts/*.sh setup.sh teardown.sh tests/*.sh
```

CI runs all three on Linux and macOS, and a pull request has to be green. The
tests take no arguments, need only `bash` and `jq`, and never touch your real
`~/.claude` — they point `CLAUDE_CONFIG_DIR` at a temporary directory and stub
the `claude` CLI. Add a case there for anything you change; the file is a flat
list of `assert_eq` calls, so a new one is two lines.

Some constraints the hooks work under, which are easy to break by accident:

- **A `UserPromptSubmit` hook must print nothing to stdout** except the JSON
  control object. Anything else is injected into the prompt as context.
- **The escape sequence is returned as JSON**, never written to `/dev/tty`, and
  Claude Code validates it against an allowlist. See
  [How it works](README.md#how-it-works).
- **`PostToolUse` fires dozens of times per turn.** Work done there has to stay
  at one file read unless the state actually needs changing.
- **Anything spawned by the hooks runs the hooks again.** The
  `WARP_TAB_CLOCK_CHILD` marker is what stops that; keep it on any new spawn.
- **Nothing derived from a prompt should reach the title unvetted.** Titles are
  persisted by Warp, and show up in screenshots and screen shares.

## Versioning

Bump `version` in `.claude-plugin/plugin.json` and add a `CHANGELOG.md` entry in
the same commit as the change. Minor for a new behaviour, patch for a fix.

## Commits

One change per commit, present tense in the subject, and a body that says what
was wrong before rather than what the diff does. `git log` is the closest thing
this project has to design documentation.
