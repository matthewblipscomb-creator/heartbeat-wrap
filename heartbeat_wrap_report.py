#!/usr/bin/env python3
"""
heartbeat_wrap_report.py

Zero-dependency (Python 3 stdlib only) analytics tool for the local
SQLite history database that heartbeat_wrap.sh's `--history` flag writes
to (default: ~/.heartbeat_wrap/history.db). Turns raw per-run rows into
actual trends, so you can answer questions like:

  - "Are my migrations getting slower over time?"
  - "This grep pattern usually takes ~40s - is this run's 3 minutes
     normal, or possibly actually stuck?"
  - "What's my overall failure rate for this job?"

Pure local file read - never makes a network call, never modifies the
history DB (read-only queries only).

USAGE
-----
  heartbeat_wrap_report.py summary  [--db PATH] [--label NAME] [--json]
  heartbeat_wrap_report.py trend    [--db PATH] [--label NAME] [--window N] [--json]
  heartbeat_wrap_report.py history  [--db PATH] [--label NAME] [--limit N] [--json]
  heartbeat_wrap_report.py baseline [--db PATH] --label NAME [--command CMD] [--json]

SUBCOMMANDS
-----------
  summary   Overall stats for all runs (or runs matching --label): count,
            min/avg/median/max elapsed seconds, failure count/rate, stuck
            count/rate, most recent run timestamp.

  trend     Splits matching runs into two halves by time (oldest half vs
            newest half) and reports whether average elapsed time is
            trending up, down, or flat. Use --window N to instead compare
            the last N runs' average against the N runs before that,
            which reacts faster to recent changes than a full 50/50 split.

  history   Raw chronological list of the most recent --limit runs
            (default 20), most recent first.

  baseline  Machine-readable single-line summary (avg/stddev/count) for
            one label (+ optional exact command match) - designed for
            heartbeat_wrap.sh's own `--history-compare` flag to consume,
            but useful standalone too.

All subcommands accept --json for machine-readable output instead of the
default human-readable text.
"""

import argparse
import json
import os
import sqlite3
import statistics
import sys
from datetime import datetime, timezone

DEFAULT_DB = os.path.expanduser("~/.heartbeat_wrap/history.db")


def fmt_elapsed(seconds):
    seconds = int(round(seconds))
    mm, ss = divmod(seconds, 60)
    hh, mm = divmod(mm, 60)
    if hh:
        return f"{hh:d}:{mm:02d}:{ss:02d}"
    return f"{mm:02d}:{ss:02d}"


def fmt_ts(ts):
    try:
        return datetime.fromtimestamp(int(ts), tz=timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return str(ts)


def open_db(path):
    if not os.path.exists(path):
        print(f"No history database found at: {path}", file=sys.stderr)
        print("(Run at least one job with `heartbeat_wrap.sh --history -- <command>` first.)", file=sys.stderr)
        sys.exit(1)
    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    return conn


def fetch_runs(conn, label=None, command=None, limit=None):
    query = "SELECT * FROM runs WHERE 1=1"
    params = []
    if label:
        query += " AND label = ?"
        params.append(label)
    if command:
        query += " AND command = ?"
        params.append(command)
    query += " ORDER BY start_ts ASC"
    if limit:
        # Need the most recent N, but ordered ascending for trend math -
        # fetch descending then reverse.
        query = query.replace("ORDER BY start_ts ASC", "ORDER BY start_ts DESC LIMIT ?")
        params.append(limit)
        rows = list(conn.execute(query, params))
        rows.reverse()
        return rows
    return list(conn.execute(query, params))


def cmd_summary(args):
    conn = open_db(args.db)
    runs = fetch_runs(conn, label=args.label)
    if not runs:
        _empty_result(args, "No matching runs found.")
        return

    elapsed = [r["elapsed_seconds"] for r in runs]
    failures = [r for r in runs if r["exit_code"] != 0]
    stuck = [r for r in runs if r["stuck_detected"]]
    last = runs[-1]

    result = {
        "label_filter": args.label,
        "count": len(runs),
        "elapsed_seconds": {
            "min": min(elapsed),
            "avg": round(statistics.mean(elapsed), 1),
            "median": round(statistics.median(elapsed), 1),
            "max": max(elapsed),
            "stddev": round(statistics.pstdev(elapsed), 1) if len(elapsed) > 1 else 0.0,
        },
        "failure_count": len(failures),
        "failure_rate_pct": round(100 * len(failures) / len(runs), 1),
        "stuck_warning_count": len(stuck),
        "stuck_warning_rate_pct": round(100 * len(stuck) / len(runs), 1),
        "most_recent_run_ts": last["start_ts"],
        "most_recent_run_at": fmt_ts(last["start_ts"]),
    }

    if args.json:
        print(json.dumps(result, indent=2))
        return

    label_desc = f"label='{args.label}'" if args.label else "all labels"
    print(f"Summary ({label_desc}) - {result['count']} run(s)")
    print("-" * 60)
    e = result["elapsed_seconds"]
    print(f"  Elapsed:  min {fmt_elapsed(e['min'])}  avg {fmt_elapsed(e['avg'])}  "
          f"median {fmt_elapsed(e['median'])}  max {fmt_elapsed(e['max'])}  "
          f"(stddev {fmt_elapsed(e['stddev'])})")
    print(f"  Failures: {result['failure_count']} / {result['count']} "
          f"({result['failure_rate_pct']}%)")
    print(f"  Stuck warnings ever fired: {result['stuck_warning_count']} / {result['count']} "
          f"({result['stuck_warning_rate_pct']}%)")
    print(f"  Most recent run: {result['most_recent_run_at']}")


def cmd_trend(args):
    conn = open_db(args.db)
    runs = fetch_runs(conn, label=args.label)
    if len(runs) < 4:
        _empty_result(args, "Not enough runs yet for a meaningful trend (need at least 4).")
        return

    if args.window:
        w = args.window
        if len(runs) < 2 * w:
            _empty_result(args, f"Not enough runs for --window {w} (need at least {2*w}, have {len(runs)}).")
            return
        older = runs[-2 * w:-w]
        newer = runs[-w:]
        older_label = f"previous {w} runs"
        newer_label = f"most recent {w} runs"
    else:
        mid = len(runs) // 2
        older = runs[:mid]
        newer = runs[mid:]
        older_label = f"older half ({len(older)} runs)"
        newer_label = f"newer half ({len(newer)} runs)"

    older_avg = statistics.mean(r["elapsed_seconds"] for r in older)
    newer_avg = statistics.mean(r["elapsed_seconds"] for r in newer)
    pct_change = ((newer_avg - older_avg) / older_avg * 100) if older_avg else 0.0

    if pct_change > 15:
        direction = "SLOWER"
    elif pct_change < -15:
        direction = "FASTER"
    else:
        direction = "FLAT"

    result = {
        "label_filter": args.label,
        "older_period": older_label,
        "older_avg_elapsed_seconds": round(older_avg, 1),
        "newer_period": newer_label,
        "newer_avg_elapsed_seconds": round(newer_avg, 1),
        "pct_change": round(pct_change, 1),
        "direction": direction,
    }

    if args.json:
        print(json.dumps(result, indent=2))
        return

    label_desc = f"label='{args.label}'" if args.label else "all labels"
    print(f"Trend ({label_desc})")
    print("-" * 60)
    print(f"  {older_label}: avg {fmt_elapsed(older_avg)}")
    print(f"  {newer_label}: avg {fmt_elapsed(newer_avg)}")
    sign = "+" if pct_change >= 0 else ""
    print(f"  Change: {sign}{result['pct_change']}%  -> trending {direction}")
    if direction == "SLOWER":
        print("  (Runs have been taking noticeably longer recently - worth investigating.)")
    elif direction == "FASTER":
        print("  (Runs have been getting faster recently - nice.)")
    else:
        print("  (No significant change - durations look stable.)")


def cmd_history(args):
    conn = open_db(args.db)
    runs = fetch_runs(conn, label=args.label, limit=args.limit)
    runs = list(reversed(runs))  # most recent first for display
    if not runs:
        _empty_result(args, "No matching runs found.")
        return

    if args.json:
        print(json.dumps([dict(r) for r in runs], indent=2, default=str))
        return

    label_desc = f"label='{args.label}'" if args.label else "all labels"
    print(f"Last {len(runs)} run(s) ({label_desc}), most recent first")
    print("-" * 78)
    for r in runs:
        status = "OK" if r["exit_code"] == 0 else f"FAILED(exit {r['exit_code']})"
        stuck_flag = " [STUCK-WARNING]" if r["stuck_detected"] else ""
        cmd_short = r["command"] if len(r["command"]) <= 40 else r["command"][:37] + "..."
        print(f"  {fmt_ts(r['start_ts'])}  {fmt_elapsed(r['elapsed_seconds']):>8}  "
              f"{status:<20}{stuck_flag}  [{r['label'] or '-'}]  {cmd_short}")


def cmd_baseline(args):
    conn = open_db(args.db)
    runs = fetch_runs(conn, label=args.label, command=args.command)
    if not runs:
        result = {"label": args.label, "command": args.command, "count": 0}
        if args.json:
            print(json.dumps(result))
        else:
            print("no_baseline count=0")
        return

    elapsed = [r["elapsed_seconds"] for r in runs]
    result = {
        "label": args.label,
        "command": args.command,
        "count": len(elapsed),
        "avg_elapsed_seconds": round(statistics.mean(elapsed), 1),
        "stddev_elapsed_seconds": round(statistics.pstdev(elapsed), 1) if len(elapsed) > 1 else 0.0,
        "max_elapsed_seconds": max(elapsed),
    }
    if args.json:
        print(json.dumps(result))
    else:
        # Single-line, easy-to-parse-from-bash format for --history-compare.
        print(f"count={result['count']} avg={result['avg_elapsed_seconds']} "
              f"stddev={result['stddev_elapsed_seconds']} max={result['max_elapsed_seconds']}")


def _empty_result(args, message):
    if args.json:
        print(json.dumps({"error": message}))
    else:
        print(message)


def build_parser():
    p = argparse.ArgumentParser(
        description="Analytics/trends over heartbeat_wrap.sh's --history SQLite log."
    )
    p.add_argument("--db", default=DEFAULT_DB, help=f"Path to history DB (default: {DEFAULT_DB})")
    sub = p.add_subparsers(dest="subcommand", required=True)

    sp = sub.add_parser("summary", help="Overall stats (count, elapsed min/avg/max, failure/stuck rates)")
    sp.add_argument("--label", default=None)
    sp.add_argument("--json", action="store_true")
    sp.set_defaults(func=cmd_summary)

    tp = sub.add_parser("trend", help="Is this job getting slower, faster, or staying flat over time?")
    tp.add_argument("--label", default=None)
    tp.add_argument("--window", type=int, default=None,
                     help="Compare last N runs vs the N before that, instead of a 50/50 split")
    tp.add_argument("--json", action="store_true")
    tp.set_defaults(func=cmd_trend)

    hp = sub.add_parser("history", help="Raw chronological list of recent runs")
    hp.add_argument("--label", default=None)
    hp.add_argument("--limit", type=int, default=20)
    hp.add_argument("--json", action="store_true")
    hp.set_defaults(func=cmd_history)

    bp = sub.add_parser("baseline", help="Machine-readable avg/stddev for one label(+command) - used by --history-compare")
    bp.add_argument("--label", required=True)
    bp.add_argument("--command", default=None)
    bp.add_argument("--json", action="store_true")
    bp.set_defaults(func=cmd_baseline)

    return p


def main():
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
