# heartbeat_wrap

**A tiny, dependency-free bash script that wraps any long-running command
and prints a periodic "hey - still here, btw" heartbeat, so you know
it's working and not hung.**

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

## Install

There's nothing to install. Just download `heartbeat_wrap.sh`, make it
executable, and run it:

```bash
chmod +x heartbeat_wrap.sh
./heartbeat_wrap.sh --interval 10 -- your-slow-command --with --its --own --flags
```

Optionally drop it somewhere on your `PATH` (e.g. `/usr/local/bin/`) to
call it from anywhere as just `heartbeat_wrap.sh`.

## Compatibility

- macOS (bash 3.2+, the default shipped version) — tested
- Linux (bash + coreutils) — should work as-is; notifications use
  `notify-send` if present
- Uses `mktemp -t heartbeat_wrap.XXXXXX`, which is compatible with both
  BSD/macOS and GNU/Linux `mktemp` implementations

## License

MIT — see [LICENSE](./LICENSE). Free to use, modify, and share, forever,
no strings attached. This is the "coffeeware" tier: fully-featured,
no paywall, no telemetry.

## Roadmap / Pro tier ideas

The free script above intentionally stays a single dependency-free bash
file — that's the whole appeal. Anything below is being considered for a
**separate, optional companion product** (working name: `heartbeat_wrap
Pro`), not gating features out of the free script:

- **Remote/team notifications** — Slack, Discord, or generic webhook
  pings instead of (or in addition to) local desktop notifications, so a
  teammate (or you, away from your desk) knows a long CI/migration/agent
  job finished or failed.
- **Local dashboard** — a lightweight menu-bar app (macOS) or small local
  web UI listing every currently-running wrapped job across all terminals,
  with live elapsed time, without needing to tail individual status files.
- **Run history & analytics** — log every wrapped run's command, duration,
  and exit code to a local SQLite file; surface trends like "your
  migrations have been getting slower" or "this grep pattern usually takes
  ~40s, this run is already at 3 minutes — maybe *is* stuck this time."
- **Smart stuck-detection** — beyond a fixed timer, watch child CPU/IO
  activity and flag jobs that look truly idle (zero CPU, zero disk I/O)
  vs. ones that are heartbeat-visible but legitimately grinding away.
- **Agent/CI native integration** — a small MCP server or CI plugin that
  auto-wraps every long shell step an AI agent or pipeline runs, so this
  becomes automatic instead of something you have to remember to type.
- **Cross-platform native notifications** — Windows support (currently
  macOS/Linux only) via `msg`/toast notifications for WSL and native
  Windows terminals.

None of this is committed or funded yet — it's a backlog of ideas from
treating this as a real product, not just a script. Feedback/PRs on which
of these would actually be worth paying for are welcome.

## Support this project

This script is free and always will be. That said, if it ever saved you
from an unnecessary restart, a wasted hour, or a wasted AI/agent session
credit — a small tip is genuinely appreciated (never required):

👉 **[Add your donation link here — e.g. Buy Me a Coffee / GitHub
Sponsors / Ko-fi / PayPal.me]**

Issues, improvements, and pull requests are welcome.
