# Agent Shell Hangs — a field guide

**Who this is for:** anyone building or driving an AI coding agent (Cline,
Claude Code, Aider, a custom CI bot, etc.) that executes shell commands
non-interactively. `heartbeat_wrap.sh` solves the *visibility* half of the
"is it stuck?" problem (see the main [README](../README.md)). This doc
catalogs the recurring *root causes* of actual hangs discovered while
building/using this tool and its companion projects — generic bash/POSIX
shell behaviors, not specific to any one machine, OS, or agent. If you're
integrating an agent with a shell, you will eventually hit these.

None of these are `heartbeat_wrap.sh` bugs — they're footguns in how
non-interactive shell execution works in general. `heartbeat_wrap.sh`'s
`--lint`/`--lint-strict` flags catch two of them automatically (see below);
the rest are avoidance patterns to build into the calling agent/workflow
itself.

---

## 1. Multi-line quoted strings → `dquote>` / `quote>` / `cmdquote>`

**Trigger:** a shell command string (e.g. a `git commit -m "line one
\nline two"`) contains an unbalanced or unexpectedly-interpreted quote
character, or a multi-line string gets sent to a shell that expects a
single logical command. The shell's line-continuation parser then sits at
a `dquote>`/`quote>` (bash) or `cmdand dquote>` (some wrappers) prompt,
silently waiting for the closing quote — indistinguishable from a genuine
hang to anything watching only for process exit.

**Fix / avoidance:**
- Never build multi-line commit messages (or any multi-line shell
  argument) via an inline `-m "..."` string. Write the message to a real
  temp file first, then pass it with `-F <path>` (e.g.
  `git commit -F /tmp/msg.txt`), and delete the temp file after.
- If a terminal is ever *found* stuck at `dquote>`/`quote>`: do not send
  more input hoping it "gets through" — that appends to the same broken
  string. Send a bare closing quote character + newline (matching whatever
  the prompt shows) or `Ctrl-C`, confirm a normal prompt returns, then
  re-issue the corrected command via the temp-file approach above.

## 2. Heredocs (`<< EOF`) — ban outright from agent-driven `execute_command`

**Trigger:** any heredoc (`<< EOF`, `<< 'EOF'`, `<<-EOF`) run through an
agent's shell-execution tool. The shell parser waits for a line matching
the closing delimiter before it will execute *anything* — if that
delimiter line is missing, mismatched, or the whole construct gets
interrupted mid-stream (e.g. the agent's tool call itself times out or
the session drops), the terminal is left stuck at a continuation prompt
(`heredoc>`, `cmdand heredoc>`), with potentially garbled/duplicated
content already written if it was for a file-append.

This is a **structural** risk, not a matter of writing the heredoc more
carefully — even a syntactically perfect heredoc is one interrupted
session away from leaving a dangling continuation prompt, because the
whole point of a heredoc is "wait for more input before running." An
agent's tool-call/response cycle is exactly the kind of interruption
surface where that assumption breaks.

**Fix / avoidance:**
- **Never use heredoc syntax in agent-driven shell execution, full stop —
  not just for file writes.** For writing/appending file content, use a
  dedicated file-write tool (not a shell command at all) if your agent
  framework has one. For a CLI tool that only accepts heredoc-style stdin
  with no file-argument alternative, write the payload to a real script
  file first and invoke `bash /path/to/script.sh`, or pipe from an actual
  file (`some-tool < payload.txt`) instead of inline heredoc syntax.
- `heartbeat_wrap.sh --lint` / `--lint-strict` will detect unterminated
  heredocs in the wrapped command string and warn (`--lint`) or refuse to
  run at all (`--lint-strict`, exits 2) — use `--lint-strict` as a safety
  net on any command string assembled programmatically, even though the
  real fix is not generating heredocs in the first place.
- If a terminal is ever found stuck at a heredoc continuation prompt, same
  recovery as case 1: bare closing delimiter + newline or `Ctrl-C`, verify
  a normal prompt, then redo the fix through a real file instead.

## 3. First-run CLI installer/`init` consent prompts hidden by a pipe

**Trigger:** running a tool's first-run `init`/`setup`/`install`
subcommand (which may ask an interactive Y/N telemetry-consent or
first-run-config question on stdin) through a pipe like `| tail -30` or
`| grep ...`. The prompt is real and is actually blocking on stdin — but
piping the output hides the visual prompt text from whatever is watching,
so it looks exactly like a silent hang.

**Fix / avoidance:**
- Before running any tool's first-run `init`/`setup` command for the
  first time in an agent-driven session, check its docs/`--help` for a
  non-interactive flag (`--yes`, `--no-input`, `-y`) or an env var that
  suppresses first-run prompts, and use it proactively.
- If no such flag exists, run the bare command first (no pipe) so any
  prompt is actually visible, answer it once, and only pipe subsequent
  invocations.
- If a run is already stuck: check for a live process blocked on its own
  TTY stdin (`ps aux` / `lsof` on the suspect PID) before assuming
  corruption — this diagnostic will show a real, running process waiting
  on input, not a crashed one. Kill it safely and re-run non-interactively
  (e.g. `echo "n" | tool init --no-patch` or the tool's documented
  equivalent).

## 4. `exec > >(tee file) 2>&1` process substitution — unreliable reaping under old bash

**Trigger:** using `exec > >(tee "$RESULTS_FILE") 2>&1` near the top of a
script to duplicate all output to both the terminal and a log file. Under
older bash (notably macOS's stock-shipped bash 3.2.57 — NOT a modern
bash, and still the default on every unmodified Mac), the backgrounded
`tee` process spawned by that process substitution is not always reliably
reaped before the parent script itself exits. A supervising process
watching for "has this script's registered job finished" (e.g. a
`heartbeat_wrap.sh`-style job registry, or any wrapper polling for exit)
can keep reporting the job as still `RUNNING` long after the actual work
finished and exited 0 — a false "stuck" signal in the *opposite*
direction from the hangs above.

**Fix / avoidance:**
- Don't use `exec > >(...)` process substitution for output-duplication
  in scripts meant to run unattended/under supervision. Wrap the whole
  script body in a `main() { ... }` function and invoke it as a plain
  pipeline instead: `main "$@" 2>&1 | tee "$logfile"` at the very bottom
  of the file. An ordinary pipeline has well-defined, portable wait
  semantics across bash versions — no background-subprocess reaping edge
  case.

---

## 5. The other failure mode: the *supervisor* crashes, not the shell

Everything above is about the wrapped **command** hanging. There's a
distinct, unrelated failure mode worth planning for separately: the
**agent/IDE process itself** crashing or losing its connection mid-session
(e.g. an editor extension host terminating) while a command was mid-flight.
This is not a shell hang at all — `heartbeat_wrap.sh` can't prevent a
supervising process from dying, because by definition it isn't the thing
that died.

What it *can* do is make that scenario recoverable instead of ambiguous:

- **Always launch anything long-running or risky as a background
  heartbeat-wrap job** (the MCP `start_heartbeat_job` tool, or
  `heartbeat_wrap.sh ... &` plus `--status-file`/`--history` on the shell
  side) rather than a plain blocking call. The wrapped command keeps
  running to completion independently of whatever launched it.
- If the supervisor comes back after a crash, **don't trust
  scrollback/memory about whether the last command finished** — re-check
  ground truth instead: the job registry (`~/.heartbeat_wrap/jobs/`,
  `check_heartbeat_job`/`list_heartbeat_jobs`), `--history`'s SQLite log,
  or (for anything that wrote real files/DB rows) the actual on-disk/DB
  state. In practice, file-write and DB-commit operations are already
  synchronous — a supervisor crash essentially never loses *already-
  executed* work; the real risk is just not knowing what state you're
  actually in afterward. Verifying ground truth before continuing costs a
  few tool calls and eliminates that uncertainty entirely.

---

*This doc is generalized from concrete incidents hit while building and
field-testing `heartbeat_wrap.sh` itself across a separate real-world
CFML/ColdFusion project. Contributions of additional hang classes (with a
reproducible trigger + fix) are welcome via PR.*
