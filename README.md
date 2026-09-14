# OpenCode Cost & Usage Panel

Live, always-visible cost and token tracking for **[OpenCode](https://opencode.ai/)**, running in a right-hand [Ghostty](https://ghostty.org/) split next to your terminal session — so you can watch what a coding agent is actually costing you, turn by turn, instead of finding out at the end of the month.

This came out of a simple problem: AI coding agents burn tokens and money per turn, per session, per day — and none of that is visible while you're working. You only find out later, from a dashboard or an invoice, by which point the expensive session is long over and you've learned nothing you can act on. This repo is the fix: a live panel that sits next to your terminal and updates every few seconds.

The same panel for Claude Code lives in **[claudecode-cost-usage-panel](https://github.com/andrewbakercloudscale/claudecode-cost-usage-panel)** — the two were one repo until they were split apart, which is why the design notes here and there cross-reference each other.

Full write-up and motivation: **[AI coding costs are guesswork without this: instrumenting OpenCode and Claude Code](https://andrewbaker.ninja/2026/08/22/ai-coding-costs-are-guesswork-without-this-instrumenting-opencode-and-claude-code/)**

## What you get

`opencode-panel-setup.sh` installs a live panel showing:

- **Per-turn breakdown** — turn, provider/model, context size, Δ cache write, cache hit %, cost — parsed from `opencode export <session>`.
- **7-day average session cost** baseline, from `opencode session list --format json`.
- **Today / last 7 days**, shown via OpenCode's own `opencode stats` output (deliberately *not* reparsed as JSON — see the note in the script header about why `opencode stats --json`'s shape isn't stable enough to trust yet).

It also installs:

- **Auto-launch on first use per window.** A `preexec` hook in `~/.zshrc` watches for the first `opencode...` command typed in a terminal window and opens the panel automatically — you never have to remember to start it.
- **tmux-aware launching.** Inside tmux the launcher uses tmux's own `split-window` instead of driving Ghostty via AppleScript — no Accessibility permission or keystroke simulation needed. This matters because tmux overrides `$TERM_PROGRAM` to `tmux` regardless of the outer terminal, so without this check the Ghostty path would silently fail to detect Ghostty even when Ghostty is the real host.
- **Auto-resize** to roughly 1/3 of the window width — via tmux's `split-window -l 33%` inside tmux, or Ghostty keybinds (`ctrl+shift+h` / `ctrl+shift+l`, added to `~/.config/ghostty/config` if missing) otherwise — then focus returns to your original pane.
- **Verified, not assumed (Ghostty path).** The launcher drives Ghostty via `osascript`/System Events, retries up to 3 times, and confirms success by checking that a new panel *process* actually exists — not just that AppleScript returned exit code 0, which it will happily do even when nothing happened.
- **Logging.** Every launch attempt is logged with a shared run ID (`~/.cache/opencode-panel-launch.log`) so a failed auto-launch is diagnosable instead of just silently missing.
- **Idempotence.** Safe to re-run any time — it overwrites the generated scripts with the latest version and skips any `.zshrc`/config block that's already present.

## How it works

The installer lays down a **panel script** (the thing that renders live stats in a loop) and a **launcher script** (the thing that opens a Ghostty split and starts the panel in it), plus a small `~/.zshrc` hook that fires the launcher automatically. A few decisions aren't obvious from the code alone:

- **Per-turn cost isn't available from OpenCode's own tooling, so the panel computes it itself.** `opencode stats` only exposes session/day-level totals, not a per-message figure. The panel instead reads the raw session transcript (`opencode export <session>`) and prices every assistant turn from its token usage: input, output, cache read, and cache write tokens, each at the provider's published per-model rate. That's what makes the "per turn" table possible — it doesn't exist anywhere else.
- **`opencode stats` is rendered, not reparsed.** `opencode session list --format json` and `opencode export <id>` both have confirmed JSON shapes and are parsed; `opencode stats --json` does not, so the today/7-day figures shell out to plain `opencode stats` and show its own output rather than guessing at field names. A guessed key that stops matching reads as a zero, not as an error — which is the exact failure this project exists to prevent. If your installed version supports `--json` on stats cleanly, that section is the one to upgrade.
- **Rendering never trusts the pane's current size to stay put.** The panel is meant to sit in a resizable split, so every frame is measured against the *current* terminal width/height (`tput cols`/`tput lines`) rather than a fixed layout, and every printed line is padded with `\033[K` (clear-to-end-of-line) so a shorter new frame can't leave stale characters from a wider previous one ghosting through.
- **The AppleScript automation verifies itself instead of trusting its own exit code.** AppleScript will report success (exit 0, no stderr) even when a stale frontmost check or an internal early `return` meant nothing actually happened — so the launcher doesn't believe it. It snapshots running panel processes before the attempt, snapshots them again after, and only calls it a success if a *new* process actually appeared.
- **Everything is idempotent by construction.** The installer checks for its own marker (a comment string in `~/.zshrc`, a grep against `~/.config/ghostty/config`) before appending anything, so re-running it after a script update never double-installs a hook or duplicates a keybind.

## Requirements

- macOS + [Ghostty](https://ghostty.org/) for the auto-split part — unless you run inside tmux, in which case tmux's own split is used instead and Ghostty isn't required. The panel script itself works in any terminal if you just run it manually.
- `jq`
- The `opencode` CLI on your `PATH`
- Accessibility permission granted to Ghostty (macOS will prompt the first time the launcher tries to drive it via System Events) — not needed for the tmux path

## Install

```bash
bash opencode-panel-setup.sh
```

Or via the wrapper, which does nothing the installer doesn't already do on its own — it's just a single command to re-run after pulling changes, mirroring the `deploy-*.sh` convention used elsewhere:

```bash
bash deploy.sh
```

Then open a **new** terminal window/tab (or `source ~/.zshrc`) and type an `opencode...` command — the panel opens automatically in a right-hand split.

You can also run the panel manually at any time, in any terminal:

```bash
~/.local/bin/opencode-panel.sh [refresh_seconds] [turn_rows]
```

## Tests

```bash
bash tests/run-tests.sh
```

Two rules the suite is built on, both learned the hard way: **gate on exit codes, never on the absence of matched output**, and **fail any check that ran zero assertions** — a gate that has quietly stopped covering anything reports "ok" forever and stops you looking.

## Design & investigation notes

[`OPENCODE-TIER-PLAN.md`](OPENCODE-TIER-PLAN.md) covers the caching and refresh-tier pass on this panel, which started with no caching at all (28.44 → 8.57 CPU-s / 60s). Read it before changing the areas it covers — it records bugs that were shipped, not just intentions.

## Troubleshooting

- **Panel never opens automatically** — check `~/.cache/opencode-panel-launch.log`. If you're outside tmux, the most common cause is Ghostty missing Accessibility permission (System Settings → Privacy & Security → Accessibility). If you're inside tmux, confirm `tmux` is actually on `$PATH` for that shell (the log will say `TMUX is set but tmux binary not found` if not).
- **Split opens but stays 50/50** — outside tmux, make sure `~/.config/ghostty/config` has the `resize_split` keybinds the installer adds (`ctrl+shift+h` / `ctrl+shift+l`); if that file didn't exist when you installed, create it and re-run the installer. Inside tmux this shouldn't happen — the launcher opens the split at 1/3 width directly via `split-window -l 33%`.
- **"Value" figures don't match my actual bill** — expected on flat-rate plans. Every $ figure is `local token count × pay-as-you-go API rate`, not a real charge — it's a proxy for how much of the model you're using, not an invoice.

## License

MIT
