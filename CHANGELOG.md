# Changelog

All notable changes to `heartbeat_wrap.sh` are documented here.

## 2.0.0

### Added
- `--lint` / `--lint-strict` — best-effort static checks run on the wrapped
  command before execution:
  - Unbalanced-quote detection via bash's own parser (`bash -n`).
  - Unterminated-heredoc detection via a dedicated delimiter scanner
    (`check_heredocs()`). This is a **separate** check from the `bash -n`
    quote check because `bash -n` does not reliably flag an unterminated
    heredoc at all on every bash version — confirmed by direct testing
    against macOS's default-shipped bash 3.2, where an unterminated
    heredoc produces no warning and a `0` exit code from `bash -n`. Relying
    on `bash -n` output text (e.g. grepping for "here-document") for this
    case was tried first and found to be unreliable; `check_heredocs()`
    instead directly scans line-by-line for `<<`/`<<-` operators and
    verifies a matching closing-delimiter line actually exists later in
    the text, independent of bash's own heredoc-parsing warnings.
  - `--lint` only warns (the wrapped command still runs regardless);
    `--lint-strict` refuses to run the command at all if anything is
    flagged, exiting `2`.
- `--stuck-kill` — opt-in, off by default. Builds on the existing
  `--stuck-detect` CPU-idle heuristic: instead of only printing a warning,
  actually terminates the wrapped process (`SIGTERM`, then `SIGKILL` after
  a 1s grace period) and exits `124` (matching the conventional `timeout`
  exit code). Implies `--stuck-detect`. Documented with an explicit
  "use at your own risk" warning in the README, since the underlying
  stuck-detection is a heuristic (a process can be idle-CPU but
  legitimately waiting on slow disk/network I/O) and killing it at the
  wrong instant can leave partial/corrupted output behind.
- `-V` / `--version` flag.
- New `action.yml` inputs: `stuck-kill`, `lint-strict`, wired through to
  the underlying flags of the same name.

### Fixed
- The original `--lint` heredoc-detection approach (grepping `bash -n`'s
  stderr for the string "here-document") never actually triggered in
  testing against a real unterminated heredoc on macOS's default bash —
  it silently reported "no issues detected" for a command that would in
  fact have its content truncated. Replaced with the dedicated
  `check_heredocs()` scanner described above, and re-verified against
  four cases (unterminated heredoc, properly-terminated heredoc,
  unbalanced quote, and a plain clean command) before shipping.

## 1.0.0

Initial public release: heartbeat printing (`--interval`, `--immediate`,
`--fun`, `--message`, `--label`), `--notify`/`--bell`, `--status-file`,
`--stuck-detect`/`--stuck-threshold` (warn-only), SQLite `--history` /
`--history-compare`, local dashboard (`--no-dashboard` to opt out),
`--webhook` (generic/Slack/Discord formats, `--webhook-on-stuck`), and the
composite GitHub Action (`action.yml`).
