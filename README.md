# heartbeat_wrap

**A tiny, dependency-free bash script that wraps any long-running command
and prints a periodic "hey - still here, btw" heartbeat, so you know
it's working and not hung.**

> ⚠️ **Use at your own risk.** Provided AS IS, no warranty (see
> [LICENSE](./LICENSE)). Most of this tool only ever observes/reports —
> it changes nothing about your wrapped command. The one exception is
> `--stuck-kill` (off by default, see below): it will forcibly terminate
> the process you wrap based on a *heuristic* (no CPU progress for N
> beats), which can be wrong for a process that's idle-CPU but
> legitimately waiting on slow disk/network I/O. Killing a process at
> the wrong instant can leave partial/corrupted output behind — only
> enable it for commands that are safe to interrupt, and keep backups of
> anything important either way.

## Why this exists

If you've ever run a slow `grep`, a big `rsync`, a database migration, or
handed a long-running command off to an AI coding agent / CI runner, you've
probably hit this: the terminal just sits there silently for a long time,
and you can't tell if it's:

- almost done, or
- genuinely frozen.

This is an especially real problem with AI coding assistants (like agentic
tools that run shell commands for you): most of them only see a command's
output **after** it fully exits — they get no partial/streaming progress.
So a command that's 90% done and one that's truly stuck look *identical*
while it's running, both to the tool and often to you. That ambiguity leads
to a very common, very avoidable habit: killing the terminal and restarting
the whole task, "just in case" — even when nothing was actually wrong.

`heartbeat_wrap.sh` fixes this by running your real command in the
background and printing a live heartbeat line to your terminal at a
regular interval for as long as it's alive, optionally paired with a
desktop notification, terminal bell, and/or a persistent status file you
can watch from anywhere. No dependencies beyond bash + coreutils, which is
every Mac and Linux machine out of the box.

## Usage

```bash
heartbeat_wrap.sh [OPTIONS] -- <command> [args...]
```

| Option | Description |
|---|---|
| `--interval SECONDS` | How often to print a heartbeat line (default: `15`) |
| `--immediate` | Print the first heartbeat right away instead of waiting a full interval — confirms the job actually started |
| `--notify` | Also fire a desktop notification each heartbeat (macOS `osascript`, Linux `notify-send` if installed; silently skipped otherwise) |
| `--bell` | Ring the terminal bell (`\a`) on each heartbeat — useful if the pane is in the background |
| `--label NAME` | Tag every heartbeat/status line with `NAME`, so you can tell concurrent wrapped jobs apart |
| `--status-file PATH` | Also write the latest heartbeat (and final DONE/FAILED state) to `PATH`, overwritten each beat — `tail -f` it from another pane at any time |
| `--fun` | Rotate through a few varied "still here" phrasings instead of repeating the same line every time |
| `--message TEXT` | Use `TEXT` as the heartbeat phrase instead of the default (or `--fun` rotation) — takes priority over `--fun` if both are given. The elapsed time/pid suffix is still appended automatically |
| `--stuck-detect` | Watch the wrapped command's CPU time (via `ps`) and print an extra "possibly stuck" warning if it hasn't advanced for `--stuck-threshold` consecutive beats. Heuristic, not proof — a command can be idle-CPU but legitimately waiting on slow disk/network I/O |
| `--stuck-threshold N` | Consecutive idle beats before warning (used with `--stuck-detect`). Default: `3` |
| `--history` | Log this run (label, command, start/end time, elapsed seconds, exit code, whether a stuck warning ever fired) to a local SQLite database for later review. Silently skipped if the `sqlite3` CLI isn't installed |
| `--history-db PATH` | Path to the SQLite history DB (implies `--history`). Default: `~/.heartbeat_wrap/history.db` |
| `--no-dashboard` | Skip writing a live job-registry snapshot to `~/.heartbeat_wrap/jobs/`. By default every run writes/updates one so the companion local dashboard (see below) can list it. Purely local, no network calls |
| `--webhook URL` | POST a JSON payload to `URL` when the wrapped command finishes (DONE or FAILED). Requires `curl`; a delivery failure (missing curl, network error, non-2xx) is only ever printed as a warning — it never affects the wrapped command's exit code |
| `--webhook-format FMT` | Shape of the JSON payload sent to `--webhook`. One of `generic` (full JSON snapshot, default), `slack` (single `text` field, Slack incoming-webhook compatible), `discord` (single `content` field, Discord webhook compatible) |
| `--webhook-on-stuck` | Also POST to `--webhook` every time a "possibly stuck" warning fires (requires `--stuck-detect` too — this flag alone does nothing) |
| `--lint` | Best-effort static check for unbalanced quotes (via bash's own parser) and unterminated heredocs (via a dedicated delimiter scanner) in the wrapped command before running it — warns only, still runs the command either way |
| `--lint-strict` | Same check as `--lint`, but refuses to run the wrapped command at all if anything is flagged (exits `2`). Implies `--lint` |
| `--stuck-kill` | ⚠️ See the risk warning above. Implies `--stuck-detect`. Instead of only warning when the stuck heuristic fires, actually terminates the wrapped command (`SIGTERM`, then `SIGKILL` after a 1s grace period) and exits `124` (matching the conventional `timeout` exit code). Off by default |
| `-V`, `--version` | Print the version number and exit |
| `-h`, `--help` | Show usage |

**Always include a literal `--`** before your real command, so this
script's own flag parser doesn't get confused by flags belonging to your
wrapped command (e.g. grep's `-r`, `-l`, `-i`, `-E`, etc.)

### Examples

```bash
# A long grep across a big repo, with desktop notification
heartbeat_wrap.sh --interval 10 --notify -- \
    grep -rliE "password" --exclude-dir=node_modules --exclude-dir=.git .

# A slow build/migration, confirm it started immediately, and tail its
# status from a second terminal window while it runs
heartbeat_wrap.sh --interval 30 --immediate \
    --status-file /tmp/migration.status --label migration -- \
    ./run_migrations.sh
#   ...meanwhile, in another pane:
#   tail -f /tmp/migration.status

# Any arbitrarily slow command, with terminal bell + fun rotating messages
heartbeat_wrap.sh --bell --fun -- rsync -av ./big-folder/ /Volumes/Backup/

# Custom heartbeat message instead of the default/fun phrasing
heartbeat_wrap.sh --message "brewing coffee, hang tight" -- ./run_migrations.sh

# Watch for real hangs (not just "slow"), and keep a permanent local
# record of every run for later review
heartbeat_wrap.sh --stuck-detect --history -- ./run_migrations.sh
```

### Sample output

```
[heartbeat:migration] Starting: ./run_migrations.sh
[heartbeat:migration] Interval: 30s | Notify: 0 | Bell: 0 | Status file: /tmp/migration.status
[heartbeat:migration] PID: 41822
[heartbeat:migration] hey - still here, btw (running 00:00, pid 41822)
[heartbeat:migration] hey - still here, btw (running 00:30, pid 41822)
[heartbeat:migration] hey - still here, btw (running 01:00, pid 41822)
[heartbeat:migration] Command finished after 01:14 with exit code 0
[heartbeat:migration] --- Output of wrapped command ---
Applying migration 004_add_indexes.sql... done.
```

The wrapped command's real output/exit code are preserved and printed
once it completes — `heartbeat_wrap.sh` just adds visibility while you
wait.

## Local dashboard

Every run (unless started with `--no-dashboard`) writes a small JSON
snapshot of itself to `~/.heartbeat_wrap/jobs/job_<start_ts>_<pid>.json`
and keeps it updated on every heartbeat. `dashboard/heartbeat_dashboard.py`
is a tiny, zero-dependency (Python 3 stdlib only) local web server that
reads that directory and shows **every** wrapped job across every
terminal/tab on the machine, live, in a browser — no need to remember
which pane a long job is running in or tail individual status files.

```bash
python3 dashboard/heartbeat_dashboard.py --port 8787
# then open http://localhost:8787/ in a browser - it polls every 2s
```

The page shows each job's state (RUNNING / STALE / DONE / FAILED), label,
command, host, PID, elapsed time, and exit code. `STALE` means the
process is gone but the registry file was never updated to a final
state — almost always because it was killed with `-9`/`SIGKILL` or the
machine slept/crashed mid-run. Nothing here ever leaves your machine;
it's a pure local file-read, no network calls beyond `localhost`.

## Run history (SQLite)

Pass `--history` (or `--history-db PATH` to pick a custom location) to
log every run — label, command, start/end time, elapsed seconds, exit
code, and whether a `--stuck-detect` warning ever fired — to a local
SQLite database (default `~/.heartbeat_wrap/history.db`). Silently
skipped with a warning if the `sqlite3` CLI isn't installed; never
blocks or fails the wrapped command itself.

```bash
heartbeat_wrap.sh --history -- ./run_migrations.sh
# ...later:
sqlite3 ~/.heartbeat_wrap/history.db "SELECT label, command, elapsed_seconds, exit_code FROM runs ORDER BY start_ts DESC LIMIT 10;"
```

## Remote/team notifications (webhooks)

Pass `--webhook URL` to get a JSON POST when the wrapped command finishes
(DONE or FAILED) — useful for Slack/Discord channel pings, a teammate's
monitoring endpoint, or your own automation, without needing to be at the
terminal (or even on the same machine) when a long job wraps up.

```bash
# Generic JSON payload (default) - full state snapshot
heartbeat_wrap.sh --webhook https://example.com/hooks/heartbeat -- ./run_migrations.sh

# Slack incoming webhook - payload shaped as {"text": "..."}
heartbeat_wrap.sh --webhook "$SLACK_WEBHOOK_URL" --webhook-format slack -- ./run_migrations.sh

# Discord webhook - payload shaped as {"content": "..."}
heartbeat_wrap.sh --webhook "$DISCORD_WEBHOOK_URL" --webhook-format discord -- ./run_migrations.sh

# Also get pinged the moment a stuck-warning fires, not just at the end
heartbeat_wrap.sh --stuck-detect --webhook "$SLACK_WEBHOOK_URL" \
    --webhook-format slack --webhook-on-stuck -- ./run_migrations.sh
```

The `generic` format's full payload looks like:

```json
{
  "event": "finished",
  "job_id": "1783097947_24292",
  "label": "migration",
  "command": "./run_migrations.sh",
  "host": "my-macbook.local",
  "pid": 24292,
  "state": "DONE",
  "elapsed_seconds": 9,
  "exit_code": 0,
  "message": "Command finished after 00:09 with exit code 0"
}
```

`event` is `"finished"` for the completion POST or `"stuck"` for a
stuck-warning POST (only sent if `--webhook-on-stuck` is also passed).
Delivery uses a 10-second `curl` timeout and never blocks or fails the
wrapped command itself — a dead/unreachable webhook endpoint only ever
prints a warning to stderr.

## GitHub Actions

This repo also ships as a self-contained composite GitHub Action
(`action.yml` at the repo root) — no vendoring or extra checkout step
needed, just point `uses:` at this repo:

```yaml
- name: Run the slow thing, with a heartbeat every 30s
  uses: matthewblipscomb-creator/heartbeat-wrap@v2   # tagged release, see CHANGELOG.md
  with:
    command: './run_migrations.sh'
    label: 'migrations'
    stuck-detect: 'true'
    webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
    webhook-format: 'slack'
```

Full input/output reference, recipes (Slack-on-finish, Slack-on-stuck,
persisting history across ephemeral runners), and CI-specific caveats
live in **[docs/GITHUB_ACTIONS.md](./docs/GITHUB_ACTIONS.md)**. A
runnable example workflow is at
[`.github/workflows/example.yml`](./.github/workflows/example.yml).

## Install


There's nothing to install. Just download `heartbeat_wrap.sh`, make it
executable, and run it:

```bash
chmod +x heartbeat_wrap.sh
./heartbeat_wrap.sh --interval 10 -- your-slow-command --with --its --own --flags
```

Optionally drop it somewhere on your `PATH` (e.g. `/usr/local/bin/`) to
call it from anywhere as just `heartbeat_wrap.sh`.

To remove everything later (the PATH copy, if any, plus the local
`~/.heartbeat_wrap/` data directory used by the dashboard/history), run
`./uninstall.sh` (asks for confirmation first; pass `--yes` to skip that).

## Compatibility

- macOS (bash 3.2+, the default shipped version) — tested
- Linux (bash + coreutils) — should work as-is; notifications use
  `notify-send` if present
- Uses `mktemp -t heartbeat_wrap.XXXXXX`, which is compatible with both
  BSD/macOS and GNU/Linux `mktemp` implementations
- The dashboard requires only Python 3 (stdlib `http.server`/`json`) —
  no `pip install` needed

## License

MIT — see [LICENSE](./LICENSE). Free to use, modify, and share, forever,
no strings attached. This is the "coffeeware" tier: fully-featured,
no paywall, no telemetry.

Current version: **2.0.0** — see [CHANGELOG.md](./CHANGELOG.md) for
release notes, or run `heartbeat_wrap.sh --version`.

## Roadmap / Pro tier ideas

The free script above intentionally stays a single dependency-free bash
file — that's the whole appeal. **Local dashboard, run history/analytics
(including trend analysis via `heartbeat_wrap_report.py`), smart
stuck-detection, cross-platform notifications (macOS/Linux/Windows via
WSL/Git Bash/MSYS2/Cygwin), and remote/team webhook notifications (Slack,
Discord, generic JSON) have all shipped** in the free script/companion
tools above. What's left below is still being considered for a
**separate, optional companion product** (working name: `heartbeat_wrap
Pro`), not gating features out of the free script:

- **Agent/CI native integration** — ✅ **shipped**, two ways:
  - A small MCP server (`Cline/MCP/heartbeat-wrap-server/`) that exposes
    `start_heartbeat_job`, `check_heartbeat_job`, `wait_for_heartbeat_job`,
    and `list_heartbeat_jobs` as MCP tools. This lets an AI coding agent
    (e.g. Cline) start a long-running command in the background and
    return immediately with a `job_id`, then poll it non-blockingly
    instead of holding a terminal hostage for the whole duration —
    exactly the workflow this whole project was originally built to
    support by hand.
  - A self-contained composite **GitHub Action** (`action.yml` at the
    repo root) for wrapping a step in a CI workflow you already have,
    with optional stuck-detection and Slack/Discord/generic webhook
    notifications straight from CI. See the
    [GitHub Actions section](#github-actions) above and
    [docs/GITHUB_ACTIONS.md](./docs/GITHUB_ACTIONS.md) for the full
    reference.


None of this is committed or funded yet — it's a backlog of ideas from
treating this as a real product, not just a script. Feedback/PRs on which
of these would actually be worth paying for are welcome.

**Also planned (future, not started):** a three-tier (Small/Medium/Large)
promotion strategy for the project itself — see
[docs/MARKETING_CAMPAIGN_STRATEGY.md](./docs/MARKETING_CAMPAIGN_STRATEGY.md).
Sequenced from $0/organic (Show HN, Reddit, the Cline community, `awesome-*`
list PRs) up through a modest paid push (Product Hunt, a niche newsletter
sponsorship, GitHub Sponsors tiers) to a larger ongoing motion (podcast/
newsletter sponsorship, content marketing, a paid creator demo) — each tier
gated on the previous one actually showing real signal first. Not scheduled
against any date; revisit whenever there's time/appetite to run the Small
tier.

## Support this project


This script is free and always will be. That said, if it ever saved you
from an unnecessary restart, a wasted hour, or a wasted AI/agent session
credit — a small tip is genuinely appreciated (never required):

👉 **[Donate via PayPal](https://paypal.me/matthewlipscomb743)**


Issues, improvements, and pull requests are welcome.
