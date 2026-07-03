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

INTERVAL=15
NOTIFY=0
BELL=0
IMMEDIATE=0
FUN=0
LABEL=""
STATUS_FILE=""

print_help() {
  sed -n '/### HELP_START/,/### HELP_END/p' "$0" | grep '^#' | grep -v '^### HELP_' | sed 's/^# \{0,1\}//'
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
    --label)
      LABEL="$2"
      shift 2
      ;;
    --status-file)
      STATUS_FILE="$2"
      shift 2
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
  echo "Usage: $0 [--interval SECONDS] [--notify] [--bell] [--immediate] [--fun] [--label NAME] [--status-file PATH] -- <command> [args...]" >&2
  echo "Run '$0 --help' for more info." >&2
  exit 1
fi

TAG="[heartbeat]"
if [[ -n "$LABEL" ]]; then
  TAG="[heartbeat:${LABEL}]"
fi

send_notification() {
  local msg="$1"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"${msg}\" with title \"heartbeat_wrap${LABEL:+ - $LABEL}\"" 2>/dev/null
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send "heartbeat_wrap${LABEL:+ - $LABEL}" "${msg}" 2>/dev/null
  fi
  # If neither tool exists, silently skip - the STDOUT heartbeat line is
  # still printed either way, so nothing is lost.
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

# mktemp usage is BSD/macOS + GNU/Linux compatible when an explicit X
# template is provided.
LOG_FILE="$(mktemp -t heartbeat_wrap.XXXXXX)"
if [[ -z "$STATUS_FILE" ]]; then
  STATUS_FILE="$(mktemp -t heartbeat_wrap_status.XXXXXX)"
fi
START_TS=$(date +%s)

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

beat() {
  local elapsed_fmt
  elapsed_fmt="$(format_elapsed "$1")"
  local phrase="hey - still here, btw"
  if [[ "$FUN" -eq 1 ]]; then
    local idx=$(( (RANDOM) % ${#FUN_MESSAGES[@]} ))
    phrase="${FUN_MESSAGES[$idx]}"
  fi
  local msg="${phrase} (running ${elapsed_fmt}, pid ${CMD_PID})"
  echo "${TAG} ${msg}"
  write_status "${TAG} RUNNING - ${msg}"
  if [[ "$NOTIFY" -eq 1 ]]; then
    send_notification "$msg"
  fi
  if [[ "$BELL" -eq 1 ]]; then
    printf '\a'
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
echo "${TAG} --- Output of wrapped command ---"
cat "$LOG_FILE"
rm -f "$LOG_FILE"

exit "$EXIT_CODE"
