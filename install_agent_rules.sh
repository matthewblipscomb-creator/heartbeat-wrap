#!/usr/bin/env bash
#
# install_agent_rules.sh — actually install the AGENT_SHELL_HANGS.md rules
# into an AI coding agent's rules file, instead of just linking a doc.
#
# By default, looks for the first agent-rules file it recognizes in the
# current directory (.clinerules, .cursorrules, CLAUDE.md, AGENTS.md, in
# that order) and appends the shell-safety rules block to it, idempotently
# (safe to run more than once — detects its own marker and skips if already
# installed). Pass --target to point at a specific file (created if it
# doesn't exist yet) or --list-targets to just see what would be detected.
#
# Deliberately does NOT use a heredoc to do this appending — see
# docs/AGENT_SHELL_HANGS.md #2 for exactly why that would be ironic. Instead
# it reads a plain template file and appends it via `cat >>`.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/templates/shell_safety_rules_block.md"
BEGIN_MARKER="<!-- BEGIN heartbeat_wrap shell-safety rules"
DEFAULT_CANDIDATES=(".clinerules" ".cursorrules" "CLAUDE.md" "AGENTS.md")

TARGET=""
LIST_ONLY=0
DRY_RUN=0

print_usage() {
  cat <<USAGE
Usage: install_agent_rules.sh [OPTIONS]

Options:
  --target FILE     Install into this specific file (created if missing).
                     If omitted, auto-detects the first existing file among:
                     ${DEFAULT_CANDIDATES[*]}
                     (in the current directory), or falls back to creating
                     .clinerules if none exist.
  --dry-run          Show what would happen, don't write anything.
  --list-targets     List the auto-detected candidate files and exit.
  -h, --help         Show this help.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      TARGET="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --list-targets)
      LIST_ONLY=1
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_usage >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$TEMPLATE" ]; then
  echo "ERROR: template not found at $TEMPLATE" >&2
  exit 1
fi

if [ "$LIST_ONLY" -eq 1 ]; then
  echo "Candidate agent-rules files in $(pwd):"
  for f in "${DEFAULT_CANDIDATES[@]}"; do
    if [ -f "$f" ]; then
      echo "  [found]     $f"
    else
      echo "  [not found] $f"
    fi
  done
  exit 0
fi

if [ -z "$TARGET" ]; then
  for f in "${DEFAULT_CANDIDATES[@]}"; do
    if [ -f "$f" ]; then
      TARGET="$f"
      break
    fi
  done
  if [ -z "$TARGET" ]; then
    TARGET=".clinerules"
    echo "No existing agent-rules file found — will create $TARGET"
  fi
fi

if [ -f "$TARGET" ] && grep -qF "$BEGIN_MARKER" "$TARGET"; then
  echo "Already installed in $TARGET (marker found) — nothing to do."
  echo "Delete the block manually and re-run this script if you want to force a refresh."
  exit 0
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] Would append the following block to: $TARGET"
  echo "---"
  cat "$TEMPLATE"
  echo "---"
  exit 0
fi

# Ensure the file exists and ends with a newline before appending, so the
# marker line doesn't get glued onto a previous line with no separation.
touch "$TARGET"
if [ -s "$TARGET" ]; then
  last_char="$(tail -c 1 "$TARGET" || true)"
  if [ "$last_char" != "" ]; then
    printf '\n' >> "$TARGET"
  fi
fi
printf '\n' >> "$TARGET"
cat "$TEMPLATE" >> "$TARGET"

echo "Installed heartbeat_wrap shell-safety rules into: $TARGET"
echo "(idempotent — safe to re-run; it will detect the marker and skip next time)"
