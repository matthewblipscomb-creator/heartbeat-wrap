#!/bin/bash
# Cross-shell-interpreter smoke test for heartbeat_wrap.sh.
#
# Purpose: heartbeat_wrap.sh has a `#!/bin/bash` shebang, but shebangs are
# only honored when a script is executed directly (./heartbeat_wrap.sh) or
# via `bash heartbeat_wrap.sh`. Some CI runners / task runners / user habits
# invoke shell scripts as `sh script.sh` unconditionally, ignoring the
# shebang entirely and forcing whatever `/bin/sh` is on that system (which on
# many Linux distros is dash, NOT bash) to parse bash-only syntax (arrays,
# [[ ]], regex =~, etc.). This test explicitly tries invoking the script via
# each interpreter's own binary to see how it fails/succeeds under each,
# rather than assuming the shebang always saves us.
#
# Written to a real .sh file per this project's own systemPatterns.md rule
# (never type multi-step test sequences inline into execute_command).
set +e

echo "=== Interpreter versions available on this host ==="
for bin in bash zsh sh dash; do
  path="$(command -v "$bin" 2>/dev/null)"
  if [[ -n "$path" ]]; then
    echo "-- $bin: $path"
    "$bin" -c 'echo "  version-ish: $0 $BASH_VERSION$ZSH_VERSION"' 2>&1
  else
    echo "-- $bin: not installed"
  fi
done

echo ""
echo "=== TEST A: ./heartbeat_wrap.sh directly (relies on shebang -> bash) ==="
chmod +x heartbeat_wrap.sh
./heartbeat_wrap.sh --interval 1 --no-dashboard -- echo "shebang-invocation-ok"
echo "exit=$?"

echo ""
echo "=== TEST B: explicit 'bash heartbeat_wrap.sh' (shebang irrelevant) ==="
bash heartbeat_wrap.sh --interval 1 --no-dashboard -- echo "bash-invocation-ok"
echo "exit=$?"

echo ""
echo "=== TEST C: explicit 'zsh heartbeat_wrap.sh' (forces zsh to parse bash syntax) ==="
zsh heartbeat_wrap.sh --interval 1 --no-dashboard -- echo "zsh-invocation-attempt"
echo "exit=$?"

echo ""
echo "=== TEST D: explicit 'sh heartbeat_wrap.sh' (on macOS, /bin/sh is bash-in-posix-mode, NOT dash) ==="
sh heartbeat_wrap.sh --interval 1 --no-dashboard -- echo "sh-invocation-attempt"
echo "exit=$?"

echo ""
echo "=== TEST E: explicit 'dash heartbeat_wrap.sh' (true POSIX dash - expected to fail on bash-only syntax) ==="
dash heartbeat_wrap.sh --interval 1 --no-dashboard -- echo "dash-invocation-attempt"
echo "exit=$?"

echo ""
echo "=== ALL CROSS-SHELL TESTS COMPLETE ==="
