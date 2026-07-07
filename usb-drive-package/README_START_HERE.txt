heartbeat_wrap.sh — Cross-Platform Field Test (USB drive edition)
===================================================================

WHY THIS EXISTS
----------------
There is no SSH/remote-access channel set up from the main dev laptop to
Cheese-Grater, Little-Alien, or Little-Kahuna, and none of those three
machines answered a ping when last checked (2026-07-07) — likely just
powered off. Rather than set up remote access, this folder can be copied
onto a USB drive, physically carried to each machine, and run locally.
No network access, no admin/root access, and no installation is required
(Windows machines only need EITHER Git Bash OR WSL already present, or a
one-time install of Git for Windows — see RUN_ON_WINDOWS.bat for details).

WHAT'S IN THIS FOLDER
----------------------
  heartbeat_wrap.sh         - exact copy of the real script being tested
                               (verified byte-for-byte identical via diff)
  run_test_mac_linux.sh     - the actual test suite (bash), safe to read
  RUN_ON_MAC_LINUX.command  - double-click launcher for macOS Finder;
                               also just `bash RUN_ON_MAC_LINUX.command`
                               works fine on a real Linux desktop too
  RUN_ON_WINDOWS.bat        - double-click launcher for Windows; auto-
                               detects Git Bash or WSL and uses whichever
                               is present, with clear install guidance if
                               neither is found
  README_START_HERE.txt     - this file

HOW TO USE, PER MACHINE
------------------------
1. Copy this whole "usb-drive-package" folder onto a USB drive.
2. Plug the drive into the target machine.
3. Run the launcher for that OS:
     - Cheese-Grater (Ubuntu Mac Pro):  double-click
       RUN_ON_MAC_LINUX.command, or open a terminal and run
       `bash run_test_mac_linux.sh` from inside this folder.
     - Little-Alien / Little-Kahuna (Windows):  double-click
       RUN_ON_WINDOWS.bat.
4. Wait for "ALL TESTS COMPLETE" to print.
5. A file named results_<hostname>_<timestamp>.txt will appear in this
   same folder — bring that file back (USB drive again, email, whatever)
   so the output can be reviewed and folded into
   heartbeat-wrap/docs/CROSS_PLATFORM_NOTES.md.

WHAT THE TEST SUITE ACTUALLY CHECKS
------------------------------------
  - Which shells are installed (bash/zsh/sh/dash) and their versions
  - ps/mktemp flavor (GNU vs BSD — affects some of heartbeat_wrap.sh's
    internal process-inspection logic)
  - heartbeat_wrap.sh invoked 5 different ways: via shebang, explicit
    bash, explicit zsh, explicit sh, explicit dash (the last two are
    EXPECTED to fail on some systems — that's a known, documented
    limitation, not a bug to chase)
  - --lint-strict correctly refusing an unterminated heredoc (exit 2)
  - --lint passing a valid heredoc through cleanly (exit 0)
  - --lint-strict passing a clean plain command through (exit 0)
  - --stuck-detect + --stuck-kill actually killing a hung `sleep 100`
    within a few seconds (exit 124)

KNOWN, ALREADY-FIXED ISSUE (for context)
------------------------------------------
An earlier version of this exact runner used
`exec > >(tee results.txt) 2>&1` to duplicate output to a results file.
That pattern was found to leave a backgrounded `tee` process not reliably
reaped under old bash (3.2, which is what macOS ships), which could make
a supervising process think the script was still "running" even after it
had actually finished. The current version uses a plain `main | tee
results.txt` pipeline instead, which has normal, well-defined wait
semantics. Confirmed clean (reaches a real terminal/DONE state promptly)
on this Mac before going on the USB drive. If a results file on some
other machine looks truncated or the terminal window seems to hang after
printing "ALL TESTS COMPLETE", that would be worth reporting back as a
new/different issue rather than assuming it's this same one.
