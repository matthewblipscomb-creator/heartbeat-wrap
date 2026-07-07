<!-- BEGIN heartbeat_wrap shell-safety rules v1 (installed by install_agent_rules.sh) -->
## Shell command safety rules (installed by heartbeat_wrap)

Full explanations/rationale: https://github.com/matthewblipscomb-creator/heartbeat-wrap/blob/main/docs/AGENT_SHELL_HANGS.md

- **Never use shell heredoc syntax** (`<< EOF`, `<< 'EOF'`, `<<-EOF`) in any
  shell-execution tool call, for any purpose — including file writes/appends.
  Use a dedicated file-write tool instead, or write the payload to a real
  script file first and invoke that file.
- **Never build a multi-line shell string argument inline** (e.g. a
  multi-line `git commit -m "..."`). Write it to a temp file first and pass
  it by path instead (e.g. `git commit -F /tmp/msg.txt`), then delete the
  temp file after.
- **Before running any CLI tool's first-run `init`/`setup`/`install`
  command**, check for a non-interactive flag (`--yes`, `--no-input`, `-y`)
  or env var and use it proactively. Don't pipe a first-run command that
  might prompt on stdin (e.g. `| tail`, `| grep`) — run it bare first so any
  prompt is actually visible.
- **Don't use `exec > >(tee file) 2>&1`** in any script meant to run
  unattended/under supervision. Wrap the script body in a `main() { ... }`
  function and invoke it as `main "$@" 2>&1 | tee "$logfile"` instead —
  ordinary pipelines have reliable wait semantics across bash versions,
  process substitution does not on some (notably macOS's stock bash 3.2).
- **If a terminal is ever found stuck** at a `dquote>`/`quote>`/`heredoc>`
  continuation prompt: do not send more input hoping it "gets through" —
  that appends to the same broken construct. Send a bare closing
  delimiter/quote + newline (matching the prompt) or `Ctrl-C`, confirm a
  normal prompt returns, then reissue the original fix through a real file
  instead of another inline multi-line string.
- **Launch long-running or risky commands as a supervised background job**
  (e.g. `heartbeat_wrap.sh` with `--status-file`/`--history`, or an
  agent-native job-runner tool) rather than a plain blocking call, so that
  if the supervising process/session itself crashes mid-run, the job's
  actual completion state can be checked afterward instead of staying
  ambiguous.
<!-- END heartbeat_wrap shell-safety rules v1 -->
