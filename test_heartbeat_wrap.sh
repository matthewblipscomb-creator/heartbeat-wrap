#!/bin/bash
# Safe re-run of the heartbeat_wrap.sh lint/stuck-kill smoke test suite.
#
# IMPORTANT: this file is executed as a real script file INSIDE the docker
# container (bash /hb-test/test_heartbeat_wrap.sh), never fed to a shell as
# an inline multi-line string. The heredocs below are safe in THIS context
# because they're parsed once, directly by the bash process running this
# very file - there is no outer execute_command shell layer trying to also
# parse this same text as part of a bigger one-line/multi-line command
# string. See memory-bank/systemPatterns.md -> "Shell heredocs - banned
# outright from execute_command" for why the ORIGINAL version of this test
# (heredocs typed directly inside a `docker run ... bash -c '...'` argument
# passed straight to execute_command) was unsafe, regardless of whether the
# heredocs inside it were intentionally-unterminated test fixtures or not.
set -e

bash --version | head -1
echo "=== ps --version ==="
ps --version 2>&1 | head -1 || true
echo "=== mktemp --version ==="
mktemp --version 2>&1 | head -1 || true
echo ""

cd /tmp && cp -r /hb ./hb && cd hb && chmod +x heartbeat_wrap.sh

echo "=== TEST 1: unterminated heredoc, lint-strict, expect exit 2 ==="
set +e
./heartbeat_wrap.sh --lint-strict --no-dashboard -- bash -c "cat << Q
unterminated"
echo "exit=$?"
set -e

echo ""
echo "=== TEST 2: valid heredoc, lint, expect clean pass ==="
set +e
./heartbeat_wrap.sh --lint --no-dashboard -- bash -c "cat << Q
fine
Q"
echo "exit=$?"
set -e

echo ""
echo "=== TEST 3: unbalanced quote, lint-strict, expect exit 2 ==="
set +e
./heartbeat_wrap.sh --lint-strict --no-dashboard -- bash -c "echo oops"
echo "exit=$?"
set -e

echo ""
echo "=== TEST 4: stuck-kill on sleep, interval 1, threshold 1 ==="
set +e
timeout 8 ./heartbeat_wrap.sh --interval 1 --stuck-detect --stuck-threshold 1 --stuck-kill --no-dashboard -- sleep 100
echo "exit=$?"
set -e

echo ""
echo "=== ALL TESTS COMPLETE ==="
