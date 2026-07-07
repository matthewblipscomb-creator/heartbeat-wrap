#!/bin/bash
# Double-clickable launcher for macOS Finder (also works fine run manually
# from a Linux terminal: `bash RUN_ON_MAC_LINUX.command`).
cd "$(dirname "$0")" || exit 1
bash run_test_mac_linux.sh
echo ""
echo "Press Enter to close this window..."
read -r _
