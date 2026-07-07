#!/bin/bash
### HELP_START
# heartbeat_wrap.sh
#
# Wrap ANY long-running shell command with a periodic "hey - still here,
# btw" heartbeat, so you get a live, visible signal in your terminal (and
# optionally a desktop notification / sound / status file) that the
# command is still working - not hung.
#
# WHY THIS EXISTS
# ----------------
# AI coding assistants and CI-style tool runners typically only see a
# command's output *after* it fully exits - they get no partial/streaming
# progress. That means a command that's 90% done and one that's truly
# stuck look identical while running, and it's easy to waste time (or
# money, on metered AI/agent sessions) restarting something that was
# actually fine and just slow.
#
# This script solves that by running your real command in the background
# and printing a heartbeat line to STDOUT (and optionally a status file,
# desktop notification, or terminal bell) at a regular interval for as
# long as it's alive. You (a human watching the terminal, or tailing the
# status file from another pane) get instant, ongoing confirmation that
# nothing has frozen.
#
# USE AT YOUR OWN RISK
# ---------------------
# Provided AS IS, no warranty (see LICENSE). Most of this tool only ever
# observes/reports - it changes nothing about your wrapped command. The
# one exception is --stuck-kill (off by default): it will forcibly
# terminate (SIGTERM, then SIGKILL) the process you wrap based on a
# HEURISTIC (no CPU progress for N beats), which can be wrong for a
# process that's idle-CPU but legitimately waiting on slow disk/network
# I/O. Killing a process at the wrong instant - mid file-write, mid DB
# transaction, mid in-place edit - can leave partial/corrupted output
# behind. Only enable --stuck-kill for commands that are safe to
# interrupt or that already have their own atomic/transactional write
# safety, and keep backups of anything important either way.
#
# USAGE
# -----
#   heartbeat_wrap.sh [OPTIONS] -- <command> [args...]
#
# OPTIONS
#   --interval SECONDS    How often to print a heartbeat line. Default: 15.
#   --notify               Also fire a desktop notification on each
#                          heartbeat (macOS via osascript, Linux via
#                          notify-send if installed; silently skipped if
#                          neither exists).
#   --bell                 Ring the terminal bell (\a) on each heartbeat -
#                          useful if the terminal pane is in the background.
#   --immediate            Print the first heartbeat right away instead of
#                          waiting a full --interval before the first one.
#                          Handy for confirming the job actually started.
#   --label NAME           Tag every heartbeat/status line with NAME, so
#                          you can tell concurrent wrapped jobs apart in a
#                          shared terminal or shared status file.
#   --status-file PATH     Also write the latest heartbeat line to PATH
#                          (overwritten each beat, plus an OK/DONE/FAILED
#                          final line). Lets you `tail -f PATH` from a
#                          separate pane/window at any time, or have a
#                          monitoring script poll it. Default: a fresh
#                          file under $TMPDIR per run (path is printed at
#                          startup); pass explicitly to reuse one path
#                          across runs.
#   --fun                  Rotate through a small set of varied "still
#                          here" phrasings instead of repeating the same
#                          line every time (purely cosmetic).
#   --message TEXT          Use TEXT as the heartbeat phrase instead of
#                          the default "hey - still here, btw" (or the
#                          --fun rotation). Takes priority over --fun if
#                          both are given. The elapsed time/pid suffix is
#                          still appended automatically.

#   --stuck-detect          Watch the wrapped command's actual CPU time
#                          (via `ps`) alongside the timer-based heartbeat.
#                          If CPU time hasn't advanced for
#                          --stuck-threshold consecutive beats, an extra
#                          "possibly stuck" warning line is printed so you
#                          can tell "legitimately grinding" apart from
#                          "truly idle" (e.g. blocked on a prompt, deadlock,
#                          or a hung network call). Heuristic, not proof -
#                          a command can be idle-CPU but legitimately
#                          waiting on slow disk/network I/O.
#   --stuck-threshold N     Consecutive idle beats before warning (used
#                          with --stuck-detect). Default: 3.
#   --history               Log this run (label, command, start/end time,
#                          elapsed seconds, exit code, whether a stuck
#                          warning ever fired) to a local SQLite database
#                          for your own later review. Fully local, no
#                          network calls, silently skipped if the
#                          `sqlite3` CLI isn't installed.
#   --history-db PATH       Path to the SQLite history DB (used with
#                          --history). Default: ~/.heartbeat_wrap/history.db
#   --history-compare       On each beat (and at the end), compare this
#                          run's elapsed time so far against the historical
#                          average for runs with the same --label, pulled
#                          from the --history SQLite DB (implies --history).
#                          If elapsed time exceeds the historical average by
#                          --history-compare-multiplier (default 2x) and at
#                          least --history-compare-min-runs past runs exist,
#                          prints an extra warning - e.g. "this grep usually
#                          takes ~40s, this run is already at 3 minutes."
#                          Silently skipped (with a note) if --label wasn't
#                          given, since matching relies on it.
#   --history-compare-multiplier N   How many times slower than the
#                          historical average triggers the warning above.
#                          Default: 2.
#   --history-compare-min-runs N     Minimum past runs (for this label)
#                          required before comparing at all. Default: 3.
#   --no-dashboard          Skip writing a live job-registry snapshot to

#                          ~/.heartbeat_wrap/jobs/. By default every run
#                          writes/updates a small JSON file there so the
#                          companion local dashboard (dashboard/heartbeat_
#                          dashboard.py) can list every wrapped job
#                          currently running across all terminals. Purely
#                          local, no network calls, silently skipped if
#                          the `sqlite3` CLI isn't installed.
#   --webhook URL           POST a JSON payload to URL when the wrapped
#                          command finishes (DONE or FAILED). Requires
#                          `curl`; silently skipped with a warning if
#                          curl isn't installed. Never blocks/fails the
#                          wrapped command - a webhook delivery failure
#                          is only ever printed as a warning.
#   --webhook-format FMT    Shape of the JSON payload sent to --webhook.
#                          One of: generic (full JSON snapshot, default),
#                          slack (single "text" field, Slack incoming-
#                          webhook compatible), discord (single "content"
#                          field, Discord webhook compatible).
#   --webhook-on-stuck      Also POST to --webhook every time a
#                          "possibly stuck" warning fires (requires
#                          --stuck-detect to actually be enabled too -
#                          this flag alone does nothing).
#   --webhook-on-history-warn   Also POST to --webhook the first time a
#                          --history-compare "HISTORY WARNING" fires for
#                          this run (requires --history-compare to
#                          actually be enabled too - this flag alone does
#                          nothing). Fires once per run, not on every
#                          beat, to avoid spamming the webhook endpoint
#                          for the remainder of a slow-but-fine run.
#   --lint                  Best-effort static check (using bash's own
#                          parser) for unbalanced quotes and unterminated
#                          heredocs in the wrapped command before running
#                          it - the exact bug class that most often leaves
#                          a shell stuck at a continuation prompt forever
#                          when run non-interactively (an AI agent/CI
#                          runner has no stdin to ever supply the missing
#                          text). Warns only; still runs the command
#                          either way.
#   --lint-strict           Same check as --lint, but refuses to run the
#                          wrapped command at all if anything is flagged
#                          (exits 2 instead). Implies --lint.
#   --stuck-kill             EXTRA RISK - see "USE AT YOUR OWN RISK" near
#                          the top of this file. Implies --stuck-detect.
#                          Instead of only warning when the CPU-idle
#                          stuck heuristic fires, actually terminates the
#                          wrapped command (SIGTERM, then SIGKILL after a
#                          1s grace period) and exits with code 124
#                          (matching the conventional `timeout` exit
#                          code). Off by default - only enable this for
#                          commands whose output is safe to interrupt
#                          mid-write, or that have their own atomic/
#                          transactional write safety.
#   -V, --version            Print the version number and exit.
#   -h, --help             Show this help text.




#
# IMPORTANT: always put a literal "--" before your real command so this
# script's own option parser doesn't get confused by your command's flags
# (e.g. grep's -r, -l, -i, -E, etc.)
#
# EXAMPLES
# --------
#   # Long grep across a big repo, with desktop notification
#   heartbeat_wrap.sh --interval 10 --notify -- \
#       grep -rliE "password" --exclude-dir=node_modules --exclude-dir=.git .
#
#   # A slow build/migration script, confirm it started immediately,
#   # and tail its status from another terminal
#   heartbeat_wrap.sh --interval 30 --immediate \
#       --status-file /tmp/migration.status --label migration -- \
#       ./run_migrations.sh
#
#   # Any arbitrarily slow command, with terminal bell + fun messages
#   heartbeat_wrap.sh --bell --fun -- rsync -av ./big-folder/ /Volumes/Backup/
#
# EXIT CODE
# ---------
# Exits with the same exit code as the wrapped command.
#
# LICENSE: MIT (see LICENSE file). Free to use, modify, and share.
# If this script ever saved you from an unnecessary restart, a small
# tip is appreciated but never required - see README.md for a link.
### HELP_END

set -uo pipefail

HEARTBEAT_WRAP_VERSION="2.0.0"

INTERVAL=15
NOTIFY=0
BELL=0
IMMEDIATE=0
FUN=0
MESSAGE=""
LABEL=""

STATUS_FILE=""
STUCK_DETECT=0
STUCK_THRESHOLD=3
STUCK_KILL=0
LINT=0
LINT_STRICT=0
HISTORY=0
HISTORY_DB=""
HISTORY_COMPARE=0
HISTORY_COMPARE_MULTIPLIER=2
HISTORY_COMPARE_MIN_RUNS=3
DASHBOARD=1

REGISTRY_DIR="${HOME}/.heartbeat_wrap/jobs"
WEBHOOK_URL=""
WEBHOOK_FORMAT="generic"
WEBHOOK_ON_STUCK=0
WEBHOOK_ON_HISTORY_WARN=0

# Declared here (not near their first real use in beat()) specifically so
# a SIGINT/SIGTERM trap firing very early - before beat() has ever run -
# can still safely reference EVER_STUCK under `set -u` without an
# "unbound variable" error inside the trap handler itself.
LAST_CPU_SECONDS=""
IDLE_BEATS=0
EVER_STUCK=0
INTERRUPTED_HANDLED=0





print_help() {
  # NOTE: the marker strings below are deliberately split with '' so this
  # line's own raw text never contains a literal "HELP_START"/"HELP_END"
  # substring. sed's /pat1/,/pat2/ range re-opens every time pat1 matches
  # anywhere in the file (including this very line, since sed re-scans
  # the whole script via "$0") - an earlier version of this line matched
  # itself, silently re-opened the range with no closing HELP_END left to
  # find, and dumped every remaining comment in the file into --help output.
  sed -n '/### HELP_STA''RT/,/### HELP_E''ND/p' "$0" | grep '^#' | grep -v '^### HELP_' | sed 's/^# \{0,1\}//'
}


while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --notify)
      NOTIFY=1
      shift
      ;;
    --bell)
      BELL=1
      shift
      ;;
    --immediate)
      IMMEDIATE=1
      shift
      ;;
    --fun)
      FUN=1
      shift
      ;;
    --message)
      MESSAGE="$2"
      shift 2
      ;;
    --label)

      LABEL="$2"
      shift 2
      ;;
    --status-file)
      STATUS_FILE="$2"
      shift 2
      ;;
    --stuck-detect)
      STUCK_DETECT=1
      shift
      ;;
    --stuck-threshold)
      STUCK_THRESHOLD="$2"
      shift 2
      ;;
    --stuck-kill)
      STUCK_KILL=1
      STUCK_DETECT=1
      shift
      ;;
    --lint)
      LINT=1
      shift
      ;;
    --lint-strict)
      LINT=1
      LINT_STRICT=1
      shift
      ;;
    -V|--version)
      echo "heartbeat_wrap.sh version ${HEARTBEAT_WRAP_VERSION}"
      exit 0
      ;;
    --history)
      HISTORY=1
      shift
      ;;
    --history-db)
      HISTORY_DB="$2"
      HISTORY=1
      shift 2
      ;;
    --history-compare)
      HISTORY_COMPARE=1
      HISTORY=1
      shift
      ;;
    --history-compare-multiplier)
      HISTORY_COMPARE_MULTIPLIER="$2"
      shift 2
      ;;
    --history-compare-min-runs)
      HISTORY_COMPARE_MIN_RUNS="$2"
      shift 2
      ;;
    --no-dashboard)

      DASHBOARD=0
      shift
      ;;
    --webhook)
      WEBHOOK_URL="$2"
      shift 2
      ;;
    --webhook-format)
      WEBHOOK_FORMAT="$2"
      shift 2
      ;;
    --webhook-on-stuck)
      WEBHOOK_ON_STUCK=1
      shift
      ;;
    --webhook-on-history-warn)
      WEBHOOK_ON_HISTORY_WARN=1
      shift
      ;;
    --)

      shift
      break
      ;;



    -h|--help)
      print_help
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [--interval SECONDS] [--notify] [--bell] [--immediate] [--fun] [--label NAME] [--status-file PATH] [--stuck-detect] [--stuck-threshold N] [--stuck-kill] [--lint] [--lint-strict] [--history] [--history-db PATH] -- <command> [args...]" >&2
  echo "Run '$0 --help' for more info." >&2
  exit 1
fi

if [[ "$HISTORY" -eq 1 && -z "$HISTORY_DB" ]]; then
  HISTORY_DB="${HOME}/.heartbeat_wrap/history.db"
fi

# Captured before anything else touches "$@", used for both --history and
# the --no-dashboard job-registry snapshots.
ORIGINAL_CMD="$*"




TAG="[heartbeat]"
if [[ -n "$LABEL" ]]; then
  TAG="[heartbeat:${LABEL}]"
fi

# --lint / --lint-strict: best-effort static check for the exact class of
# bug that motivated adding this feature - a heredoc (`<< EOF`) with no
# matching closing delimiter, or unbalanced quoting, either of which can
# leave a real interactive shell stuck at a continuation prompt forever
# when run non-interactively (an AI agent/CI runner has no stdin to ever
# supply the missing text). Uses bash's own parser (`bash -n`) rather
# than hand-rolled quote-counting, so it's as accurate as bash itself -
# but it's still a HEURISTIC about *what* to check: it inspects the
# command string as given, so cleverly-nested constructs it doesn't know
# to unwrap can still evade it. --lint warns only; --lint-strict refuses
# to run the wrapped command at all if anything is flagged.
#
# Uses a here-string (<<<), never a heredoc (<<), to feed bash -n - a
# here-string is a single already-fully-expanded value with no closing
# delimiter to wait for, so unlike a real heredoc it can never itself
# hang waiting on more input.
# Scans $1 line-by-line for a heredoc operator (<< or <<-, but not the
# unrelated <<< here-string) and verifies a line consisting solely of its
# delimiter word appears somewhere later in the text (with <<-, leading
# tabs on the closing line are stripped first, matching real shell
# behavior). Prints one message per unterminated heredoc found, or
# nothing at all if none are found. Bash-3.2-compatible (no mapfile),
# since that's still macOS's default shipped bash.
check_heredocs() {
  local text="$1"
  local -a lines=()
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    lines+=("$line")
  done <<< "$text"

  local n=${#lines[@]}
  local re="<<(-)?[[:space:]]*['\"]?([A-Za-z_][A-Za-z0-9_]*)"
  local i j strip delim cand found
  for (( i=0; i<n; i++ )); do
    if [[ "${lines[$i]}" =~ $re ]]; then
      strip="${BASH_REMATCH[1]}"
      delim="${BASH_REMATCH[2]}"
      found=0
      for (( j=i+1; j<n; j++ )); do
        cand="${lines[$j]}"
        if [[ -n "$strip" ]]; then
          while [[ "$cand" == $'\t'* ]]; do
            cand="${cand#?}"
          done
        fi
        if [[ "$cand" == "$delim" ]]; then
          found=1
          break
        fi
      done
      if [[ "$found" -eq 0 ]]; then
        echo "unterminated heredoc: delimiter '${delim}' opened on line $(( i + 1 )) of the wrapped command, but no matching closing line found later (bash would silently auto-close it at end-of-input, truncating your content, instead of ever finding your intended closing delimiter)."
      fi
    fi
  done
}

lint_command() {
  local -a cmd_args=("$@")
  local script_to_check

  # If invoked as `bash/sh/zsh -c "<script>"` (the pattern this project's
  # own action.yml, and most CI/agent wrappers, use), lint the actual
  # script text (arg 3) rather than the joined "$*" of the outer three
  # args - the outer array already has correct argument boundaries;
  # re-joining it with spaces would destroy that and cause false
  # positives.
  if [[ "${#cmd_args[@]}" -ge 3 && "${cmd_args[0]}" =~ ^(bash|sh|zsh)$ && "${cmd_args[1]}" == "-c" ]]; then
    script_to_check="${cmd_args[2]}"
  else
    script_to_check="${cmd_args[*]}"
  fi

  local lint_output lint_exit
  lint_output="$(bash -n <<< "$script_to_check" 2>&1)"
  lint_exit=$?

  local found=0
  if [[ "$lint_exit" -ne 0 ]]; then
    echo "${TAG} LINT: bash reports a syntax error in the wrapped command (often unbalanced quotes):" >&2
    echo "$lint_output" | sed 's/^/  /' >&2
    found=1
  fi

  # bash -n alone does NOT reliably flag an unterminated heredoc (bash
  # silently auto-closes it at end-of-input with no warning at all on
  # some bash versions, including macOS's default 3.2) - confirmed by
  # direct testing, not assumed. So heredoc-closing-delimiter checking is
  # done separately here, by literally scanning for `<<`/`<<-` operators
  # and verifying a matching closing-delimiter line exists later in the
  # text - the exact same thing a human reviewing the command by eye
  # would check for.
  local heredoc_issues
  heredoc_issues="$(check_heredocs "$script_to_check")"
  if [[ -n "$heredoc_issues" ]]; then
    echo "${TAG} LINT: ${heredoc_issues}" >&2
    found=1
  fi

  if [[ "$found" -eq 1 ]]; then
    if [[ "$LINT_STRICT" -eq 1 ]]; then
      echo "${TAG} LINT-STRICT: refusing to run (see warnings above). Re-run without --lint-strict to proceed anyway, or fix the command." >&2
      exit 2
    else
      echo "${TAG} LINT: proceeding anyway (--lint warns only; use --lint-strict to refuse instead)." >&2
    fi
  else
    echo "${TAG} LINT: no issues detected."
  fi
}

if [[ "$LINT" -eq 1 || "$LINT_STRICT" -eq 1 ]]; then
  lint_command "$@"
fi

send_notification() {
  local msg="$1"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${msg}\" with title \"heartbeat_wrap${LABEL:+ - $LABEL}\"" 2>/dev/null
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "heartbeat_wrap${LABEL:+ - $LABEL}" "${msg}" 2>/dev/null
  elif command -v powershell.exe >/dev/null 2>&1; then
    # Windows, reached via WSL / Git Bash / MSYS2 / Cygwin (native Windows
    # has no osascript/notify-send, but all of these bash flavors can
    # shell out to the real powershell.exe on PATH). Uses a plain WinForms
    # balloon-tip notification - no BurntToast or any other extra module
    # required, works out of the box on any Windows 10/11 install.
    #
    # NOTE: written to a temp .ps1 file (rather than passed inline as a
    # -Command string) specifically to avoid shell-quoting fragility -
    # see the .clinerules "dquote> hang" lessons this project has already
    # hit more than once with inline multi-quoted strings. Launched fully
    # backgrounded (never waited on) so a slow/hidden PowerShell start can
    # never delay or block the heartbeat loop itself; the script
    # self-deletes its own temp file when it exits.
    #
    # Best-effort: WSL2's own /tmp isn't natively visible to the Windows
    # powershell.exe binary via a plain path, so this attempts a path
    # translation (wslpath under WSL, cygpath under Git Bash/MSYS2/Cygwin)
    # and falls back to the raw path if neither tool is present. Written
    # without a live Windows/WSL box to test against - please report back
    # via a GitHub issue if this needs adjusting for your setup.
    local ps1 win_path esc_title esc_msg
    esc_title="heartbeat_wrap${LABEL:+ - $LABEL}"
    esc_msg="$msg"
    ps1="${TMPDIR:-/tmp}/heartbeat_wrap_notify_$$_${RANDOM}.ps1"
    if command -v wslpath >/dev/null 2>&1; then
      win_path="$(wslpath -w "$ps1" 2>/dev/null || echo "$ps1")"
    elif command -v cygpath >/dev/null 2>&1; then
      win_path="$(cygpath -w "$ps1" 2>/dev/null || echo "$ps1")"
    else
      win_path="$ps1"
    fi
    cat > "$ps1" <<PS1SCRIPT 2>/dev/null
Add-Type -AssemblyName System.Windows.Forms
\$n = New-Object System.Windows.Forms.NotifyIcon
\$n.Icon = [System.Drawing.SystemIcons]::Information
\$n.Visible = \$true
\$n.ShowBalloonTip(5000, "${esc_title}", "${esc_msg}", [System.Windows.Forms.ToolTipIcon]::Info)
Start-Sleep -Seconds 6
\$n.Dispose()
Remove-Item -Path '$ps1' -Force -ErrorAction SilentlyContinue
PS1SCRIPT
    powershell.exe -NoProfile -WindowStyle Hidden -File "$win_path" >/dev/null 2>&1 &
  fi
  # If none of the above tools exist, silently skip - the STDOUT
  # heartbeat line is still printed either way, so nothing is lost.
}


# POSTs a JSON payload to $WEBHOOK_URL, shaped according to
# $WEBHOOK_FORMAT ("generic" | "slack" | "discord"). Called on final
# DONE/FAILED (always, if --webhook is set) and optionally on stuck
# warnings (if --webhook-on-stuck is also set). Requires `curl`; any
# failure here (missing curl, network error, non-2xx response) is only
# ever printed as a warning to stderr - it must never affect the exit
# code or behavior of the wrapped command itself. A short timeout keeps
# a dead/unreachable webhook endpoint from ever hanging the whole run.
send_webhook() {
  local event="$1" message="$2" state="$3" elapsed="$4" exit_code_json="${5:-null}"

  [[ -n "$WEBHOOK_URL" ]] || return
  if ! command -v curl >/dev/null 2>&1; then
    echo "${TAG} --webhook requested but 'curl' not found - skipping webhook delivery." >&2
    return
  fi

  local payload
  case "$WEBHOOK_FORMAT" in
    slack)
      payload="{\"text\": \"$(json_escape "${TAG} ${message}")\"}"
      ;;
    discord)
      payload="{\"content\": \"$(json_escape "${TAG} ${message}")\"}"
      ;;
    *)
      payload="{\"event\": \"$(json_escape "$event")\", \"job_id\": \"$(json_escape "${JOB_ID:-}")\", \"label\": \"$(json_escape "$LABEL")\", \"command\": \"$(json_escape "$ORIGINAL_CMD")\", \"host\": \"$(json_escape "$HOST_NAME")\", \"pid\": ${CMD_PID:-0}, \"state\": \"$(json_escape "$state")\", \"elapsed_seconds\": ${elapsed}, \"exit_code\": ${exit_code_json}, \"message\": \"$(json_escape "$message")\"}"
      ;;
  esac

  curl --max-time 10 -fsS -X POST -H 'Content-Type: application/json' \
    -d "$payload" "$WEBHOOK_URL" >/dev/null 2>&1 \
    || echo "${TAG} WARNING: webhook delivery to ${WEBHOOK_URL} failed (event: ${event})." >&2
}


# Fun, rotating phrasing pool (used only with --fun). Kept short and
# unambiguous so it's still obviously a liveness heartbeat, not noise.
FUN_MESSAGES=(
  "hey - still here, btw"
  "still chugging along, not stuck"
  "yep, still alive over here"
  "no news is good news - still running"
  "just checking in - all good, still working"
)

format_elapsed() {
  local total="$1"
  local mm=$(( total / 60 ))
  local ss=$(( total % 60 ))
  printf "%02d:%02d" "$mm" "$ss"
}

# Reads the wrapped process's cumulative CPU time via `ps -o time=`, which
# reports [[dd-]hh:]mm:ss on both BSD/macOS and GNU/Linux ps. Returns the
# total in seconds, or "" if the process can't be read (e.g. just exited).
# This is a heuristic signal only - a command can have zero CPU time while
# legitimately blocked on slow disk/network I/O, so --stuck-detect warns
# rather than kills anything.
get_cpu_seconds() {
  local pid="$1"
  local raw
  raw="$(ps -o time= -p "$pid" 2>/dev/null | tr -d ' ')"
  if [[ -z "$raw" ]]; then
    echo ""
    return
  fi
  local days=0 hh=0 mm=0 ss=0
  if [[ "$raw" == *-* ]]; then
    days="${raw%%-*}"
    raw="${raw#*-}"
  fi
  IFS=':' read -r a b c <<< "$raw"
  if [[ -n "$c" ]]; then
    hh="$a"; mm="$b"; ss="$c"
  elif [[ -n "$b" ]]; then
    mm="$a"; ss="$b"
  else
    ss="$a"
  fi
  # macOS/BSD ps reports fractional seconds (e.g. "00.01") - truncate to
  # whole seconds since we only need coarse idle-vs-progressing signal.
  ss="${ss%%.*}"
  days="${days:-0}"; hh="${hh:-0}"; mm="${mm:-0}"; ss="${ss:-0}"
  echo $(( 10#$days*86400 + 10#$hh*3600 + 10#$mm*60 + 10#$ss ))

}

# Minimal JSON string escaping - only handles what our own field values
# can actually contain (backslash, double quote, newline). Not a general
# JSON encoder; kept dependency-free on purpose.
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

# Writes one row to the --history SQLite DB (label, command, start/end
# time, elapsed seconds, exit code, whether a stuck warning ever fired).
# Shared by both the normal DONE/FAILED completion path AND the
# SIGINT/SIGTERM cleanup_on_signal() handler below, so an interrupted run
# gets logged the same way a normal one does instead of just vanishing
# from history. No-op if --history wasn't requested; silently skipped
# (with a one-time warning) if the sqlite3 CLI isn't installed - never
# allowed to affect the wrapped command's own exit code.
log_history() {
  local exit_code="$1" elapsed="$2" end_ts="$3" ever_stuck="$4"
  [[ "$HISTORY" -eq 1 ]] || return
  if ! command -v sqlite3 >/dev/null 2>&1; then
    echo "${TAG} --history requested but 'sqlite3' CLI not found - skipping history logging." >&2
    return
  fi
  mkdir -p "$(dirname "$HISTORY_DB")" 2>/dev/null
  # SQLite quoting: double any single quotes in free-text fields.
  local escaped_cmd escaped_label
  escaped_cmd="$(printf '%s' "$ORIGINAL_CMD" | sed "s/'/''/g")"
  escaped_label="$(printf '%s' "$LABEL" | sed "s/'/''/g")"
  sqlite3 "$HISTORY_DB" <<SQL 2>/dev/null
CREATE TABLE IF NOT EXISTS runs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  label TEXT,
  command TEXT,
  start_ts INTEGER,
  end_ts INTEGER,
  elapsed_seconds INTEGER,
  exit_code INTEGER,
  stuck_detected INTEGER
);
INSERT INTO runs (label, command, start_ts, end_ts, elapsed_seconds, exit_code, stuck_detected)
VALUES ('${escaped_label}', '${escaped_cmd}', ${START_TS}, ${end_ts}, ${elapsed}, ${exit_code}, ${ever_stuck});
SQL
  echo "${TAG} Run logged to history: ${HISTORY_DB}"
}

# Handles SIGINT (Ctrl-C) / SIGTERM sent to heartbeat_wrap.sh itself while
# it's waiting on the wrapped command. Without this, hitting Ctrl-C to
# stop watching heartbeats either silently orphaned the real wrapped
# command in the background (still running, no more heartbeats, no way
# to tell) or left LOG_FILE/the registry's job_*.json stuck in "RUNNING"
# forever (only ever cleared out a day later by prune_registry's mtime
# check) - a dangling-resource bug with the exact same "silently leaves
# a mess behind" flavor as the shell hangs this whole project's
# .clinerules already catalogs at length.
#
# On interrupt: stop the real wrapped command (TERM, then KILL after a
# 1s grace period if it ignored that), mark status file/registry/history
# as INTERRUPTED (a new, explicit state - not lumped in with FAILED) so
# the dashboard and history report can tell "I stopped this on purpose"
# apart from "it exited with a real error code", fire the webhook if
# configured, clean up the temp log file, then exit with the conventional
# 128+signum code (130 for INT, 143 for TERM) so callers/CI can still
# detect this was a signal-triggered stop.
cleanup_on_signal() {
  local sig="$1"
  if [[ "$INTERRUPTED_HANDLED" -eq 1 ]]; then
    # Already mid-cleanup from a first Ctrl-C; a second one just forces
    # an immediate exit rather than re-running (and possibly tangling)
    # the cleanup steps a second time.
    exit 130
  fi
  INTERRUPTED_HANDLED=1

  local now elapsed elapsed_fmt exit_code
  now=$(date +%s)
  elapsed=$(( now - START_TS ))
  elapsed_fmt="$(format_elapsed "$elapsed")"

  echo "" >&2
  echo "${TAG} Caught ${sig} - stopping wrapped command (pid ${CMD_PID:-none started yet}) and cleaning up..." >&2

  if [[ -n "${CMD_PID:-}" ]] && kill -0 "$CMD_PID" 2>/dev/null; then
    kill -TERM "$CMD_PID" 2>/dev/null
    sleep 1
    if kill -0 "$CMD_PID" 2>/dev/null; then
      kill -KILL "$CMD_PID" 2>/dev/null
    fi
  fi

  write_status "${TAG} INTERRUPTED after ${elapsed_fmt} (${sig}, pid ${CMD_PID:-none})"
  write_registry "INTERRUPTED" "$elapsed" "null"
  send_webhook "interrupted" "Command interrupted by ${sig} after ${elapsed_fmt}" "INTERRUPTED" "$elapsed" "null"

  if [[ "$sig" == "SIGINT" ]]; then
    exit_code=130
  else
    exit_code=143
  fi
  log_history "$exit_code" "$elapsed" "$now" "$EVER_STUCK"

  rm -f "${LOG_FILE:-}" 2>/dev/null
  echo "${TAG} INTERRUPTED after ${elapsed_fmt} - exiting with code ${exit_code}." >&2
  exit "$exit_code"
}

# Called from beat() when --stuck-kill is enabled and the CPU-idle
# stuck-detect threshold has been reached. Unlike cleanup_on_signal()
# (triggered by the USER hitting Ctrl-C), this is the tool itself
# deciding to terminate the wrapped command based on a HEURISTIC (no CPU
# progress for N beats) - it can be wrong for a process that's idle-CPU
# but legitimately waiting on slow disk/network I/O. Off by default;
# only runs at all if --stuck-kill was explicitly passed. See the
# "USE AT YOUR OWN RISK" section near the top of this file before
# enabling this for anything whose output isn't safe to interrupt
# mid-write.
kill_for_stuck() {
  local elapsed="$1"
  local elapsed_fmt
  elapsed_fmt="$(format_elapsed "$elapsed")"
  local msg="--stuck-kill: terminating pid ${CMD_PID} after ${IDLE_BEATS} idle beats (~$(( IDLE_BEATS * INTERVAL ))s) with no CPU progress."
  echo "" >&2
  echo "${TAG} ${msg}" >&2

  if kill -0 "$CMD_PID" 2>/dev/null; then
    kill -TERM "$CMD_PID" 2>/dev/null
    sleep 1
    if kill -0 "$CMD_PID" 2>/dev/null; then
      kill -KILL "$CMD_PID" 2>/dev/null
    fi
  fi

  write_status "${TAG} STUCK_KILLED after ${elapsed_fmt} (pid ${CMD_PID}, ${IDLE_BEATS} idle beats)"
  write_registry "STUCK_KILLED" "$elapsed" "null"
  send_webhook "stuck_kill" "$msg" "STUCK_KILLED" "$elapsed" "null"
  log_history 124 "$elapsed" "$(date +%s)" 1

  rm -f "${LOG_FILE:-}" 2>/dev/null
  echo "${TAG} STUCK_KILLED after ${elapsed_fmt} - exiting with code 124 (matches the conventional 'timeout' exit code)." >&2
  exit 124
}

HOST_NAME="$(hostname 2>/dev/null || echo unknown)"


# Best-effort cleanup of old finished-job registry snapshots so
# ~/.heartbeat_wrap/jobs/ doesn't grow forever. Runs once per invocation,
# before this run's own entry is written. Never touches anything but its
# own job_*.json files, and any failure here is silently ignored - it's
# purely housekeeping for the optional dashboard, never load-bearing for
# the wrapped command itself.
prune_registry() {
  [[ "$DASHBOARD" -eq 1 ]] || return
  mkdir -p "$REGISTRY_DIR" 2>/dev/null || return
  find "$REGISTRY_DIR" -maxdepth 1 -name 'job_*.json' -mtime +1 -delete 2>/dev/null
}

# Writes (atomically, via a temp file + mv) a full snapshot of this run's
# current state to its own file under $REGISTRY_DIR, for the companion
# dashboard (dashboard/heartbeat_dashboard.py) to poll. Overwrites the
# same file every call, same "latest single truth" pattern as
# write_status(). Silently does nothing if --no-dashboard was passed or
# if the registry dir can't be created/written (e.g. read-only $HOME) -
# this must never be allowed to interrupt the wrapped command.
write_registry() {
  [[ "$DASHBOARD" -eq 1 ]] || return
  [[ -n "${REGISTRY_FILE:-}" ]] || return
  mkdir -p "$REGISTRY_DIR" 2>/dev/null || return
  local state="$1" elapsed="$2" exit_code_json="${3:-null}"
  local tmp
  tmp="$(mktemp "${REGISTRY_DIR}/.tmp.XXXXXX" 2>/dev/null)" || return
  cat > "$tmp" <<JSON 2>/dev/null
{
  "job_id": "${JOB_ID}",
  "pid": ${CMD_PID:-0},
  "label": "$(json_escape "$LABEL")",
  "command": "$(json_escape "$ORIGINAL_CMD")",
  "host": "$(json_escape "$HOST_NAME")",
  "start_ts": ${START_TS},
  "last_update_ts": $(date +%s),
  "interval": ${INTERVAL},
  "status_file": "$(json_escape "$STATUS_FILE")",
  "state": "${state}",
  "elapsed_seconds": ${elapsed},
  "exit_code": ${exit_code_json}
}
JSON
  mv "$tmp" "$REGISTRY_FILE" 2>/dev/null
}


# mktemp usage is BSD/macOS + GNU/Linux compatible when an explicit X

# template is provided.
LOG_FILE="$(mktemp -t heartbeat_wrap.XXXXXX)"
if [[ -z "$STATUS_FILE" ]]; then
  STATUS_FILE="$(mktemp -t heartbeat_wrap_status.XXXXXX)"
fi

# Safety net: guarantees LOG_FILE is removed no matter how the script
# exits (normal completion, an unexpected early `exit`, etc.), on top of
# the explicit `rm -f "$LOG_FILE"` already in the normal completion path
# below. $LOG_FILE is deliberately unquoted-at-registration (single
# quotes below) so this picks up its actual value when the trap fires,
# not whatever it was at registration time - it's already been set by
# mktemp above either way.
trap 'rm -f "$LOG_FILE" 2>/dev/null' EXIT

START_TS=$(date +%s)
prune_registry


write_status() {

  # Overwrite (not append) so `tail -f` / `cat` always shows the latest
  # single line of truth, no matter how many beats have happened.
  echo "$1" > "$STATUS_FILE" 2>/dev/null
}

echo "${TAG} Starting: $*"
echo "${TAG} Interval: ${INTERVAL}s | Notify: ${NOTIFY} | Bell: ${BELL} | Status file: ${STATUS_FILE}"
write_status "${TAG} STARTING: $* (pid pending)"

# Run the actual command in the background; its output is captured to a
# log file so it doesn't interleave oddly with heartbeat lines, and is
# printed in full once the command completes.
"$@" > "$LOG_FILE" 2>&1 &
CMD_PID=$!

echo "${TAG} PID: ${CMD_PID}"
write_status "${TAG} RUNNING (pid ${CMD_PID}, elapsed 00:00)"

JOB_ID="${START_TS}_${CMD_PID}"
REGISTRY_FILE="${REGISTRY_DIR}/job_${JOB_ID}.json"
write_registry "RUNNING" 0 null

# Now that the wrapped command is actually running (CMD_PID known), wire
# up Ctrl-C/SIGTERM handling so stopping heartbeat_wrap.sh itself also
# stops the real command and leaves a clean INTERRUPTED record behind
# instead of an orphaned background process + a registry entry stuck in
# "RUNNING" forever. See cleanup_on_signal()'s own comment above for the
# full rationale.
trap 'cleanup_on_signal SIGINT' INT
trap 'cleanup_on_signal SIGTERM' TERM


# --history-compare: fetch the historical baseline (avg elapsed seconds +
# run count) for this --label ONCE, right after the wrapped command
# starts. Cached in BASELINE_AVG/BASELINE_COUNT so every later beat just
# does cheap in-memory arithmetic instead of re-querying SQLite each
# time. Matches by label only (not exact command string), since the same
# logical job's command line often varies slightly run to run (paths,
# args, timestamps). Deliberately placed after "$@" is already launched
# in the background so this one-time SQLite read never delays starting
# the actual wrapped command.
BASELINE_AVG=""
BASELINE_COUNT=0
if [[ "$HISTORY_COMPARE" -eq 1 ]]; then
  if [[ -z "$LABEL" ]]; then
    echo "${TAG} --history-compare requested but no --label given - skipping (matching relies on --label)." >&2
  elif ! command -v sqlite3 >/dev/null 2>&1; then
    echo "${TAG} --history-compare requested but 'sqlite3' CLI not found - skipping." >&2
  elif [[ -f "$HISTORY_DB" ]]; then
    ESCAPED_LABEL_LOOKUP="$(printf '%s' "$LABEL" | sed "s/'/''/g")"
    BASELINE_ROW="$(sqlite3 -separator '|' "$HISTORY_DB" \
      "SELECT COUNT(*), COALESCE(AVG(elapsed_seconds), 0) FROM runs WHERE label = '${ESCAPED_LABEL_LOOKUP}';" 2>/dev/null)"
    if [[ -n "$BASELINE_ROW" ]]; then
      BASELINE_COUNT="${BASELINE_ROW%%|*}"
      BASELINE_AVG="${BASELINE_ROW##*|}"
    fi
    if [[ "${BASELINE_COUNT:-0}" -ge "$HISTORY_COMPARE_MIN_RUNS" ]]; then
      echo "${TAG} History baseline for label '${LABEL}': avg $(format_elapsed "${BASELINE_AVG%%.*}") over ${BASELINE_COUNT} past run(s). Will warn if this run exceeds ${HISTORY_COMPARE_MULTIPLIER}x that."
    else
      echo "${TAG} --history-compare: only ${BASELINE_COUNT:-0} past run(s) for label '${LABEL}' (need ${HISTORY_COMPARE_MIN_RUNS}) - comparison will stay silent until more history builds up."
      BASELINE_AVG=""
    fi
  else
    echo "${TAG} --history-compare: no history DB yet at ${HISTORY_DB} - comparison will stay silent until more history builds up." >&2
  fi
fi
HISTORY_COMPARE_WARNED=0

beat() {

  local elapsed_fmt
  elapsed_fmt="$(format_elapsed "$1")"
  local phrase="hey - still here, btw"
  if [[ -n "$MESSAGE" ]]; then
    phrase="$MESSAGE"
  elif [[ "$FUN" -eq 1 ]]; then
    local idx=$(( (RANDOM) % ${#FUN_MESSAGES[@]} ))
    phrase="${FUN_MESSAGES[$idx]}"
  fi

  local msg="${phrase} (running ${elapsed_fmt}, pid ${CMD_PID})"
  echo "${TAG} ${msg}"
  write_status "${TAG} RUNNING - ${msg}"
  write_registry "RUNNING" "$1" null

  if [[ "$NOTIFY" -eq 1 ]]; then
    send_notification "$msg"
  fi
  if [[ "$BELL" -eq 1 ]]; then
    printf '\a'
  fi

  if [[ "$HISTORY_COMPARE" -eq 1 && -n "$BASELINE_AVG" ]]; then
    local threshold
    threshold="$(awk -v a="$BASELINE_AVG" -v m="$HISTORY_COMPARE_MULTIPLIER" 'BEGIN { printf "%.0f", a * m }' 2>/dev/null)"
    if [[ -n "$threshold" && "$1" -gt "$threshold" ]]; then
      local ratio
      ratio="$(awk -v e="$1" -v a="$BASELINE_AVG" 'BEGIN { if (a > 0) printf "%.1f", e / a; else print "?" }' 2>/dev/null)"
      local hwarn="this run is already at ${elapsed_fmt}, ${ratio}x this label's historical average of $(format_elapsed "${BASELINE_AVG%%.*}") (over ${BASELINE_COUNT} past runs) - might be worth checking if it's stuck rather than just slow."
      echo "${TAG} HISTORY WARNING: ${hwarn}"
      if [[ "$HISTORY_COMPARE_WARNED" -eq 0 ]]; then
        if [[ "$NOTIFY" -eq 1 ]]; then
          send_notification "HISTORY WARNING: ${hwarn}"
        fi
        if [[ "$WEBHOOK_ON_HISTORY_WARN" -eq 1 ]]; then
          send_webhook "history_warning" "$hwarn" "HISTORY_WARNING" "$1" "null"
        fi
      fi
      HISTORY_COMPARE_WARNED=1
    fi
  fi

  if [[ "$STUCK_DETECT" -eq 1 ]]; then
    local cpu_now
    cpu_now="$(get_cpu_seconds "$CMD_PID")"

    if [[ -n "$cpu_now" ]]; then
      if [[ -n "$LAST_CPU_SECONDS" && "$cpu_now" -eq "$LAST_CPU_SECONDS" ]]; then
        IDLE_BEATS=$(( IDLE_BEATS + 1 ))
      else
        IDLE_BEATS=0
      fi
      LAST_CPU_SECONDS="$cpu_now"
      if [[ "$IDLE_BEATS" -ge "$STUCK_THRESHOLD" ]]; then
        EVER_STUCK=1
        local warn="possibly stuck - no CPU progress for ${IDLE_BEATS} beats (~$(( IDLE_BEATS * INTERVAL ))s), pid ${CMD_PID}. Could be a real hang, or a legitimate wait on disk/network I/O."
        echo "${TAG} WARNING: ${warn}"

        write_status "${TAG} POSSIBLY STUCK - ${warn}"
        if [[ "$NOTIFY" -eq 1 ]]; then
          send_notification "WARNING: ${warn}"
        fi
        if [[ "$WEBHOOK_ON_STUCK" -eq 1 ]]; then
          send_webhook "stuck" "$warn" "STUCK" "$1" "null"
        fi

        if [[ "$STUCK_KILL" -eq 1 ]]; then
          kill_for_stuck "$1"
        fi
      fi
    fi
  fi
}



if [[ "$IMMEDIATE" -eq 1 ]]; then
  NOW=$(date +%s)
  beat "$(( NOW - START_TS ))"
fi

while kill -0 "$CMD_PID" 2>/dev/null; do
  sleep "$INTERVAL"
  if kill -0 "$CMD_PID" 2>/dev/null; then
    NOW=$(date +%s)
    beat "$(( NOW - START_TS ))"
  fi
done

wait "$CMD_PID"
EXIT_CODE=$?

NOW=$(date +%s)
ELAPSED=$(( NOW - START_TS ))
ELAPSED_FMT="$(format_elapsed "$ELAPSED")"

if [[ "$EXIT_CODE" -eq 0 ]]; then
  FINAL_STATE="DONE"
else
  FINAL_STATE="FAILED"
fi

echo "${TAG} Command finished after ${ELAPSED_FMT} with exit code ${EXIT_CODE}"
write_status "${TAG} ${FINAL_STATE} after ${ELAPSED_FMT} (exit code ${EXIT_CODE})"
write_registry "$FINAL_STATE" "$ELAPSED" "$EXIT_CODE"
send_webhook "finished" "Command finished after ${ELAPSED_FMT} with exit code ${EXIT_CODE}" "$FINAL_STATE" "$ELAPSED" "$EXIT_CODE"

log_history "$EXIT_CODE" "$ELAPSED" "$NOW" "$EVER_STUCK"

echo "${TAG} --- Output of wrapped command ---"

cat "$LOG_FILE"
rm -f "$LOG_FILE"

exit "$EXIT_CODE"

