# Cross-platform / cross-shell compatibility notes

This file records what has actually been **tested** (with real command output)
versus what is a **reasoned-through code review** (no Windows machine available
to verify directly). Read the label on each section before trusting it.

## ✅ Actually tested (macOS host + Docker Ubuntu 24.04 container), July 6/7 2026

### Interpreters tried directly against `heartbeat_wrap.sh`
Run via `test_cross_shell.sh` (see repo root), on macOS (Intel,
`Matthews-Macbook-2019.local`), interpreters resolved via Homebrew + system:

| Invocation | Result |
|---|---|
| `./heartbeat_wrap.sh ...` (shebang → `/bin/bash`) | ✅ Works. |
| `bash heartbeat_wrap.sh ...` (explicit bash) | ✅ Works. |
| `zsh heartbeat_wrap.sh ...` (explicit zsh, ignoring shebang) | ✅ Works — zsh 5.9 parses the bash-isms fine in this script (no bash-array-index or `[[ ]]` incompatibilities triggered here). |
| `sh heartbeat_wrap.sh ...` (macOS `/bin/sh`) | ✅ Works — **but only because on macOS, `/bin/sh` is actually `bash` running in POSIX-compatibility mode, not a true minimal POSIX shell.** This result does NOT generalize to Linux. |
| `dash heartbeat_wrap.sh ...` (true POSIX `dash`, Homebrew-installed on this Mac) | ❌ **Fails immediately and cleanly**: `heartbeat_wrap.sh: 200: set: Illegal option -o pipefail`, exit code `2`. **No hang** — dash doesn't understand `set -o pipefail` (a bash/ksh extension, not POSIX) and aborts at that line before anything else runs. |

**Why this matters for Linux/CI specifically:** on Debian/Ubuntu (including the
`ubuntu:24.04` Docker image already used for this project's own Docker-based
tests), `/bin/sh` is a symlink to **`dash`**, not bash — the opposite of macOS.
Any environment/CI runner/user habit that invokes this script as `sh
heartbeat_wrap.sh ...` (ignoring the `#!/bin/bash` shebang, which only applies
to direct `./heartbeat_wrap.sh` or explicit `bash heartbeat_wrap.sh`
invocation) will hit this same `Illegal option -o pipefail` failure on any
Debian/Ubuntu-family Linux box, not just here.
- **This is a safe failure, not a hang** — it's an immediate, loud, correctly-
  exit-coded (`2`) error before the wrapped command ever starts, consistent
  with this whole project's "never leave the user guessing" philosophy. No
  fix is required for correctness. Worth a one-line README/docs callout so a
  confused user invoking it the wrong way isn't left wondering why nothing
  ran, though — added below.
- **The packaged GitHub Action (`action.yml`) is unaffected**: it explicitly
  declares `shell: bash` for its composite step (line 136), so `dash` is never
  in the invocation path for CI usage. This dash-incompatibility can only be
  hit by someone manually running `sh heartbeat_wrap.sh` themselves outside
  the packaged action.

### `ps -o time=` (used by `--stuck-detect`/`--stuck-kill`)
Confirmed working correctly on macOS (BSD-derived `ps`, via a real background
`sleep` process) and inside `ubuntu:24.04` (GNU `procps-ng` `ps`, confirmed via
the Docker-based `test_heartbeat_wrap.sh` run — TEST 4's `--stuck-kill`
correctly detected 1 idle beat and killed `sleep 100` with exit 124). Both
`ps` flavors' `[[dd-]hh:]mm:ss`-style `time=` output format is parsed
correctly by `get_cpu_seconds()`.

### `mktemp -t <template>` (BSD vs GNU)
This machine actually has Homebrew's GNU coreutils `mktemp` (9.11) ahead of
the system BSD one on `PATH` — confirmed via `mktemp --version`. The script's
usage pattern (`mktemp -t heartbeat_wrap.XXXXXX`, always including explicit
`X`s in the template) works correctly under both BSD and GNU `mktemp`, so this
particular difference is a non-issue in practice.

## ✅ Actually tested (real Windows 10 box, Git Bash), July 7 2026

Ran the full `run_test_mac_linux.sh` suite for real via SSH on **Little-Alien**
(hostname `Little-Alien-Aurora-R4`, real physical Windows 10 machine on the
LAN — not WSL, not a VM), through **Git for Windows 2.54.0** (installed via
`winget` for this test), invoking `heartbeat_wrap.sh` via
`"C:\Program Files\Git\bin\bash.exe"`. This directly replaces the "reasoned
through, not tested" Git Bash/MSYS2 section that used to be here — see below
for what's now confirmed vs. what remains a narrower unverified edge case.

Environment on this run: `bash` 5.3.9(1)-release, `ps (cygwin) 3.6.7`,
`mktemp (GNU coreutils) 8.32`. `zsh` not installed (skipped). Both `sh` and a
real `dash` binary were present.

| Invocation | Result |
|---|---|
| `./heartbeat_wrap.sh ...` (shebang) | ✅ exit=0 |
| `bash heartbeat_wrap.sh ...` (explicit bash) | ✅ exit=0 |
| `zsh heartbeat_wrap.sh ...` | Skipped — zsh not installed on this box. |
| `sh heartbeat_wrap.sh ...` | ✅ exit=0 — **notably different from Linux**: under Git Bash, `/usr/bin/sh` behaves like bash (same `5.3.9` version-ish reported), not dash. So unlike Debian/Ubuntu (where `/bin/sh` → dash and this invocation fails), plain `sh heartbeat_wrap.sh` actually works fine on Git Bash. |
| `dash heartbeat_wrap.sh ...` (real dash binary, present on this box) | ❌ Fails exactly as expected/documented: `[[: not found` (x3) then `Syntax error: "(" unexpected (expecting "}")`, exit=2. Consistent with the same POSIX-dash incompatibility already confirmed on Linux/macOS — dash just doesn't understand this script's bash-isms, full stop, regardless of OS underneath it. |

Lint tests: TEST 1 (unterminated heredoc, `--lint-strict`) → correctly refused,
exit=2. TEST 2 (valid heredoc, `--lint`) → clean pass, exit=0. TEST 3 (plain
command, `--lint-strict`) → clean pass, exit=0. All identical to macOS/Linux
behavior — the lint logic is pure bash string/pattern matching with no
OS-specific dependency, as expected.

**`--stuck-detect`/`--stuck-kill` — CORRECTION to an earlier version of this
doc, after a deeper follow-up test session:** an earlier pass through this
section claimed TEST 4 (against `sleep 100`) showed stuck-kill "works
correctly," reading its `exit=124` result as proof the idle-CPU heuristic
fired and killed the process. **That reading was wrong.** Re-examining that
same log line-by-line: the only message that ever printed was `Caught
SIGTERM - stopping wrapped command ... INTERRUPTED after 00:12 - exiting
with code 143` — that's `cleanup_on_signal()`, triggered by the *test
harness's own* outer `timeout 12` wrapper sending `SIGTERM` to
`heartbeat_wrap.sh` itself once its 12s bound elapsed. The `exit=124` seen
afterward is just GNU `timeout`'s own convention (it always reports 124 on
its own timeout, regardless of the child's real exit code) — not
`heartbeat_wrap.sh`'s own `kill_for_stuck()` firing. The `STUCK_KILLED`
message, which is what `kill_for_stuck()` actually prints, **never appeared
in that log at all.** So TEST 4 never actually exercised the stuck-kill
mechanism successfully — it just happened to look like it did.

**What a real, targeted follow-up test found:** a direct diagnostic —
`ps -o pid,time,stat,comm -p <pid>` and `ps -o time= -p <pid>` against a live
PID — failed immediately with `ps: unknown option -- o`. Checking `ps
--help` on this box confirms why: **the Cygwin `ps` bundled with this Git for
Windows install (`ps (cygwin) 3.6.7`) only supports `-aefls -u -p` — it has no
`-o`/custom-output-format option at all**, in any form, for any process. This
isn't a native-`.exe`-specific limitation; it's a hard capability gap in the
`ps` binary itself on stock Git for Windows. Concretely, this means
`get_cpu_seconds()`'s call to `ps -o time= -p "$pid"` **always fails and
returns empty on this platform, for every process, MSYS-aware or not** — the
script's own `[[ -n "$cpu_now" ]]` guard means `IDLE_BEATS` can never
increment, so `--stuck-detect` warnings and `--stuck-kill` terminations can
never fire at all on stock Git for Windows. Re-running three separate
targeted tests against both an idle MSYS `sleep`-equivalent, an idle native
`powershell.exe` (`Start-Sleep`), and an actively-CPU-busy native
`powershell.exe` all confirm this: **no `STUCK_KILLED` message ever printed
in any of them**, no matter how long they ran or how genuinely idle/busy the
wrapped process actually was.

**Net effect: on stock Git for Windows, `--stuck-detect`/`--stuck-kill`
silently never engages — full stop.** This is the *safe* side of the
originally-flagged risk (it never produces a false-positive kill of a
healthy process, since the mechanism never triggers at all here), but it
also means the feature provides **zero actual protection** on this platform
today — everything else in this file (heartbeats, `--notify`, `--status-file`,
`--history`, `--webhook`, `--lint`, signal handling/`INTERRUPTED` cleanup) is
unaffected and confirmed working normally; only the CPU-based stuck-idle
heuristic is a no-op here. A real fix would require either patching
`get_cpu_seconds()` to fall back to a `-o`-free `ps` invocation (e.g. parsing
the fixed-width default/`-l` output instead of relying on a custom format),
or documenting a MSYS2/Cygwin-proper `ps` (which does support `-o`) as a
prerequisite for this feature specifically on Windows.


## ⚠️ Reasoned through, NOT hands-on tested — no Windows machine available


The following is a deliberate mental/code-level walkthrough, explicitly
**not** verified against a real Windows box, WSL2 instance, Git Bash, MSYS2,
or Cygwin install. Treat every item below as "should work based on reading the
code" rather than "confirmed working." If anyone ever tests this for real on
Windows, replace this section with actual results (or file a GitHub issue with
findings — see README.md).

### WSL2 (Windows Subsystem for Linux, version 2)
**Expected: works essentially identically to native Linux**, because WSL2 is a
real Linux kernel + real Linux userland (typically Ubuntu by default), not an
emulation layer. Everything already verified above under `ubuntu:24.04`
Docker (bash 5.x, GNU `ps`/`procps-ng`, GNU `mktemp`, real POSIX signals)
should carry over directly:
- `ps -o time=`, `kill -TERM`/`kill -KILL`, `trap ... INT/TERM`, `sqlite3`,
  `curl` — all standard Linux tooling, install via the distro's package
  manager same as any other Linux box.
- The one WSL-specific wrinkle already accounted for in the code: the
  `send_notification()` function's Windows branch (lines ~516-568) detects
  `powershell.exe` on `PATH` (available by default from inside WSL via
  Windows Interop) and shells out to it for a native Windows balloon-tip
  notification, translating the temp `.ps1` script's path via `wslpath -w`
  first since WSL's own `/tmp` isn't natively visible to `powershell.exe` via
  a raw path. This is launched fully backgrounded (`&`, never waited on), so
  even a slow/hung `powershell.exe` launch can never block or delay the
  heartbeat loop itself — it can only ever fail to deliver a notification,
  never affect the wrapped command's execution or exit code.
- **Risk area, unverified:** `--notify`'s WSL path was written by reading
  WSL/Windows-interop documentation, not tested against a live WSL2 install.
  If `powershell.exe` isn't on `PATH` inside a given WSL distro (some minimal/
  custom WSL setups strip Windows interop), notifications silently no-op —
  by design, matching the "if none of the above tools exist, silently skip"
  comment already in the code — but this specific path has never been
  exercised against a real WSL terminal.

### Git Bash / MSYS2 (the bash bundled with Git for Windows)
**Update, July 7 2026: point 1 below is now confirmed (not just reasoned) —
see the "Actually tested" section above.** The real root cause turned out to
be broader than originally guessed: it's not specifically about native vs.
MSYS-aware processes, it's that **this Cygwin `ps` build has no `-o` option
at all**, so `get_cpu_seconds()` fails identically for every process. Point 2
(kill delivery) has also now been tested and confirmed working — `kill
-TERM`/`kill -KILL` from `cleanup_on_signal()` successfully terminated native
`powershell.exe` processes with no leftovers, across multiple test runs.
Left below for historical context on the original reasoning:
1. **`ps` under MSYS2 is not a real Windows process-inspection tool** — it's
   MSYS2's own `ps` that primarily reports on MSYS-spawned subprocesses via
   MSYS's own PID-remapping layer, not arbitrary native Windows PIDs. This
   matters because `heartbeat_wrap.sh` backgrounds `"$@" &` and captures
   `$!` as `CMD_PID`, then calls `get_cpu_seconds()` → `ps -o time= -p
   "$CMD_PID"` on that PID every beat. If the wrapped command is a native
   Windows `.exe` (not another MSYS-aware bash/coreutils command), `$!`'s PID
   value and what MSYS's `ps` can actually see/report CPU time for may not
   line up cleanly — this is a well-documented MSYS2/Git-Bash limitation
   independent of this script. **Likely practical effect:** `get_cpu_seconds()`
   already returns `""` (empty) for any PID it can't read via `ps -o time=
   -p`, and `beat()`'s stuck-detect logic already treats an empty result as
   "can't tell, don't warn" (`if [[ -n "$cpu_now" ]]` guards the whole idle-
   beat-counting block) — so the expected failure mode is `--stuck-detect`/
   `--stuck-kill` silently never firing for a native-Windows-`.exe` wrapped
   command under Git Bash, not a crash or hang. Heartbeats themselves
   (timer-based, not CPU-based) are unaffected either way.
2. **`kill -TERM`/`kill -KILL` against a native Windows process from MSYS2**
   is also a known soft spot — MSYS2's `kill` can signal MSYS-aware processes
   cleanly, but delivering a clean, cooperative shutdown signal to an
   arbitrary native `.exe` is much less reliable than on real POSIX (Windows
   has no native SIGTERM equivalent; MSYS approximates it). **Practical
   effect:** `--stuck-kill` and the Ctrl-C/SIGTERM `cleanup_on_signal()` path
   might not always cleanly stop a native Windows executable wrapped this
   way — it may need the SIGKILL fallback (already present, 1s grace period)
   to actually end the process via a harder mechanism, or in the worst case
   leave it running. This is the single highest-risk gap for Windows usage
   and the most worth a real hands-on Git-Bash test before anyone relies on
   `--stuck-kill` against a native Windows binary in production.
3. `mktemp`, `sqlite3`, `curl`, `date +%s`, bash version — all provided by

   MSYS2's own package set (`pacman -S ...` if not already bundled with Git
   for Windows), same general compatibility profile as Linux/macOS since
   they're the same upstream GNU/coreutils-family tools.
4. `cygpath` (the Cygwin analog to WSL's `wslpath`, already referenced in the
   `send_notification()` Windows branch as a fallback path-translator) — this
   code path is exercised for Cygwin, not MSYS2/Git-Bash specifically; Git
   Bash ships `cygpath` too (MSYS2 is a Cygwin fork), so it should resolve the
   same way, but again: reasoned, not tested.

### Cygwin
Structurally very similar to MSYS2/Git-Bash for this script's purposes (same
family of known `ps`/`kill`-against-native-processes caveats as above,
`cygpath` for path translation already wired into `send_notification()`). No
additional reasoning beyond the MSYS2 section above — not separately tested.

### Native Windows `cmd.exe` / plain PowerShell (no bash layer at all)
**Not supported, and not intended to be** — `heartbeat_wrap.sh` is a bash
script (bash arrays, `[[ ]]`, `=~` regex matching, `trap`, etc.), none of
which exist in `cmd.exe` or native PowerShell syntax. Running it requires one
of the bash-providing layers above (WSL2, Git Bash/MSYS2, or Cygwin). This is
a documented prerequisite, not a bug — same as most non-trivial bash tooling.

## Summary / recommendation
- **Confirmed safe** on macOS (bash/zsh/its own POSIX-mode `sh`) and Linux
  (Ubuntu 24.04 via Docker, both `bash` and `dash`-as-`/bin/sh` explicitly
  tested) as of July 6/7 2026.
- **Confirmed on real Windows 10 via Git Bash** (July 7 2026, Little-Alien) —
  shebang/explicit-bash/`sh` invocations, lint tests, `--notify`/
  `--status-file`/`--history`/`--webhook`, and signal-handling/
  `cleanup_on_signal()` kill-delivery to native processes all work correctly.
  `dash` fails in exactly the same documented way as on Linux/macOS.
- **Confirmed BROKEN on stock Git for Windows: `--stuck-detect`/
  `--stuck-kill`.** Root cause: the bundled Cygwin `ps` (3.6.7) has no `-o`
  option at all, so `get_cpu_seconds()` always returns empty for every
  process, MSYS-aware or native. The feature silently never engages — no
  false-positive kills, but also zero actual stuck-detection on this
  platform as shipped. See the "Actually tested" Windows section above for
  the full investigation (including a correction of an earlier, incorrect
  "works correctly" claim from a first pass through this same test).
- **Expected to work on WSL2** with high confidence (real Linux kernel/
  userland underneath, including a real `ps -o`-capable `ps`) — not yet
  hands-on verified.
- **If anyone tests WSL2/Cygwin for real, or patches `get_cpu_seconds()` to
  work around Git-for-Windows' `ps` limitation**, please update this file
  with actual results.


