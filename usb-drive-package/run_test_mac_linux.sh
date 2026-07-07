#!/bin/bash
# heartbeat_wrap.sh cross-platform field test — native macOS/Linux runner.
#
# Run this ON THE TARGET MACHINE ITSELF (Cheese-Grater Ubuntu box, or any
# other Mac/Linux machine) via a USB drive — no network/SSH access to this
# machine is required from the controlling laptop. Just plug in the drive
# and run:
#
#   cd /path/to/usb-drive/usb-drive-package
#   bash run_test_mac_linux.sh
#
# This writes a results_<hostname>_<timestamp>.txt file into this same
# folder. Bring that file back (USB drive, email, whatever) so it can be
# folded into docs/CROSS_PLATFORM_NOTES.md.
#
# Nothing here requires root/Administrator — it only reads process info via
# `ps` and runs short-lived local test commands (echo, sleep, cat).
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

HOSTNAME_SAFE="$(hostname 2>/dev/null | tr -c 'A-Za-z0-9._-' '_')"
TS="$(date +%Y%m%d_%H%M%S)"
RESULTS_FILE="$SCRIPT_DIR/results_${HOSTNAME_SAFE}_${TS}.txt"

# All actual test logic lives inside main() and is invoked via a plain
# `| tee` pipeline at the very bottom of this file, NOT via
# `exec > >(process substitution) 2>&1`. That process-substitution pattern
# was tried first and confirmed BROKEN under macOS's stock bash 3.2 (and
# is flaky on older bash generally): the backgrounded `tee` co-process
# isn't reliably reaped before the script's own exit, so a supervising
# wrapper/job-monitor can see the job as still "running" indefinitely even
# though every test already completed with a real exit code. A plain
# pipeline (`main ... | tee file`) has ordinary, well-defined wait
# semantics for both sides of the pipe and does not have this problem.
main() {
echo "############################################################"

echo "# heartbeat_wrap.sh cross-platform field test"
echo "# Host:      $(hostname 2>/dev/null)"
echo "# Date:      $(date)"
echo "# uname -a:  $(uname -a)"
echo "# whoami:    $(whoami)"
echo "############################################################"
echo ""

echo "=== Interpreter versions available on this host ==="
for bin in bash zsh sh dash; do
  path="$(command -v "$bin" 2>/dev/null)"
  if [[ -n "$path" ]]; then
    echo "-- $bin: $path"
    "$bin" -c 'echo "  version-ish: $BASH_VERSION$ZSH_VERSION"' 2>&1
  else
    echo "-- $bin: not installed"
  fi
done

echo ""
echo "=== ps --version ==="
ps --version 2>&1 | head -1 || ps -V 2>&1 | head -1 || echo "(no --version/-V support — likely BSD ps, that's fine)"
echo "=== mktemp --version ==="
mktemp --version 2>&1 | head -1 || echo "(no --version support — likely BSD mktemp, that's fine)"

chmod +x heartbeat_wrap.sh

echo ""
echo "=== TEST A: ./heartbeat_wrap.sh directly (relies on shebang -> bash) ==="
./heartbeat_wrap.sh --interval 1 --no-dashboard -- echo "shebang-invocation-ok"
echo "exit=$?"

echo ""
echo "=== TEST B: explicit 'bash heartbeat_wrap.sh' ==="
bash heartbeat_wrap.sh --interval 1 --no-dashboard -- echo "bash-invocation-ok"
echo "exit=$?"

if command -v zsh >/dev/null 2>&1; then
  echo ""
  echo "=== TEST C: explicit 'zsh heartbeat_wrap.sh' (forces zsh to parse bash syntax) ==="
  zsh heartbeat_wrap.sh --interval 1 --no-dashboard -- echo "zsh-invocation-attempt"
  echo "exit=$?"
else
  echo ""
  echo "=== TEST C: zsh not installed, skipped ==="
fi

echo ""
echo "=== TEST D: explicit 'sh heartbeat_wrap.sh' (on Linux, /bin/sh is usually dash - EXPECTED TO FAIL, that's fine and documented) ==="
sh heartbeat_wrap.sh --interval 1 --no-dashboard -- echo "sh-invocation-attempt"
echo "exit=$?"

if command -v dash >/dev/null 2>&1; then
  echo ""
  echo "=== TEST E: explicit 'dash heartbeat_wrap.sh' (true POSIX dash - EXPECTED TO FAIL on 'set -o pipefail', that's fine and documented) ==="
  dash heartbeat_wrap.sh --interval 1 --no-dashboard -- echo "dash-invocation-attempt"
  echo "exit=$?"
else
  echo ""
  echo "=== TEST E: dash not installed, skipped ==="
fi

echo ""
echo "=== TEST 1: unterminated heredoc, --lint-strict, expect exit 2 ==="
./heartbeat_wrap.sh --lint-strict --no-dashboard -- bash -c "cat << Q
unterminated"
echo "exit=$?"

echo ""
echo "=== TEST 2: valid heredoc, --lint, expect clean pass (exit 0) ==="
./heartbeat_wrap.sh --lint --no-dashboard -- bash -c "cat << Q
fine
Q"
echo "exit=$?"

echo ""
echo "=== TEST 3: plain clean command, --lint-strict, expect exit 0 ==="
./heartbeat_wrap.sh --lint-strict --no-dashboard -- bash -c "echo oops"
echo "exit=$?"

echo ""
echo "=== TEST 4: --stuck-detect + --stuck-kill against 'sleep 100', interval 1, threshold 1 (expect exit 124 within ~8s) ==="
timeout 12 ./heartbeat_wrap.sh --interval 1 --stuck-detect --stuck-threshold 1 --stuck-kill --no-dashboard -- sleep 100
echo "exit=$?"

echo ""
echo "############################################################"
echo "# ALL TESTS COMPLETE on $(hostname 2>/dev/null)"
echo "# Results saved to: $RESULTS_FILE"
echo "# Please bring this file back for review."
echo "############################################################"
}

# Plain pipeline — both sides have normal, well-defined wait semantics
# (unlike `exec > >(tee ...)`, see the comment above main()).
main 2>&1 | tee "$RESULTS_FILE"

