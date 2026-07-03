#!/usr/bin/env python3
"""
heartbeat_dashboard.py

A tiny, zero-dependency local web dashboard for heartbeat_wrap.sh.

Every `heartbeat_wrap.sh` run (unless started with --no-dashboard) writes a
small JSON snapshot of itself to ~/.heartbeat_wrap/jobs/job_<start_ts>_<pid>.json
and keeps it updated on every heartbeat. This script serves a single HTML
page + a small JSON API that reads that directory and shows every wrapped
job across every terminal/tab on this machine, live, in a browser.

USAGE
-----
    python3 dashboard/heartbeat_dashboard.py [--port 8787] [--registry-dir PATH]

Then open http://localhost:8787/ in a browser. The page polls the API
every 2 seconds; no build step, no external packages, stdlib only.

Ctrl-C to stop. This never modifies anything under the registry dir - it
only reads job_*.json files there.
"""

import argparse
import json

import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DEFAULT_REGISTRY_DIR = os.path.join(os.path.expanduser("~"), ".heartbeat_wrap", "jobs")
DEFAULT_PORT = 8787

# How long (seconds) a finished (DONE/FAILED) job stays listed after its
# last update before the dashboard stops showing it. Purely a display
# filter - registry files themselves are pruned by heartbeat_wrap.sh
# itself (1 day), independent of this.
FINISHED_DISPLAY_WINDOW = 60 * 30  # 30 minutes


def pid_alive(pid: int) -> bool:
    """Best-effort liveness check. True if the PID exists (even if not
    owned by us - a PermissionError still means it exists)."""
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def load_jobs(registry_dir: str):
    jobs = []
    try:
        names = os.listdir(registry_dir)
    except FileNotFoundError:
        return jobs
    now = time.time()
    for name in names:
        if not (name.startswith("job_") and name.endswith(".json")):
            continue
        path = os.path.join(registry_dir, name)
        try:
            with open(path, "r") as f:
                job = json.load(f)
        except (OSError, json.JSONDecodeError):
            # Could be a half-written file caught mid-write despite the
            # atomic mv in heartbeat_wrap.sh - just skip it this poll,
            # it'll be readable next time.
            continue

        state = job.get("state", "UNKNOWN")
        pid = job.get("pid", 0)
        alive = pid_alive(pid)

        if state == "RUNNING" and not alive:
            # The process is gone but the registry file was never
            # updated to DONE/FAILED - most likely killed with -9/-KILL,
            # or the machine slept/crashed mid-run.
            state = "STALE"

        if state == "RUNNING":
            live_elapsed = int(now - job.get("start_ts", now))
        else:
            live_elapsed = job.get("elapsed_seconds", 0)

        # Filter out old finished jobs so the list doesn't grow forever
        # between heartbeat_wrap.sh's own once-a-day prune.
        if state in ("DONE", "FAILED"):
            age = now - job.get("last_update_ts", now)
            if age > FINISHED_DISPLAY_WINDOW:
                continue

        jobs.append({
            "job_id": job.get("job_id", name),
            "pid": pid,
            "pid_alive": alive,
            "label": job.get("label", ""),
            "command": job.get("command", ""),
            "host": job.get("host", ""),
            "start_ts": job.get("start_ts", 0),
            "last_update_ts": job.get("last_update_ts", 0),
            "interval": job.get("interval", 0),
            "status_file": job.get("status_file", ""),
            "state": state,
            "elapsed_seconds": live_elapsed,
            "exit_code": job.get("exit_code"),
        })

    # RUNNING/STALE first (most recently started first), then finished
    # (most recently finished first).
    def sort_key(j):
        active_rank = 0 if j["state"] in ("RUNNING", "STALE") else 1
        return (active_rank, -j["start_ts"])

    jobs.sort(key=sort_key)
    return jobs


def format_elapsed(total_seconds: int) -> str:
    total_seconds = max(0, int(total_seconds))
    mm, ss = divmod(total_seconds, 60)
    hh, mm = divmod(mm, 60)
    if hh:
        return f"{hh:02d}:{mm:02d}:{ss:02d}"
    return f"{mm:02d}:{ss:02d}"


PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>heartbeat_wrap dashboard</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  :root {
    --bg: #0f1115;
    --panel: #171a21;
    --border: #262b36;
    --text: #e6e6e6;
    --muted: #8a8f98;
    --running: #3fb950;
    --stale: #d29922;
    --done: #58a6ff;
    --failed: #f85149;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
    padding: 24px;
  }
  h1 {
    font-size: 18px;
    font-weight: 600;
    margin: 0 0 4px 0;
  }
  .sub {
    color: var(--muted);
    font-size: 12px;
    margin-bottom: 20px;
  }
  table {
    width: 100%;
    border-collapse: collapse;
    background: var(--panel);
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
  }
  th, td {
    text-align: left;
    padding: 10px 12px;
    font-size: 13px;
    border-bottom: 1px solid var(--border);
  }
  th {
    color: var(--muted);
    font-weight: 500;
    text-transform: uppercase;
    font-size: 11px;
    letter-spacing: 0.04em;
  }
  tr:last-child td { border-bottom: none; }
  code {
    background: #0d1017;
    padding: 2px 6px;
    border-radius: 4px;
    font-size: 12px;
    color: #c9d1d9;
  }
  .badge {
    display: inline-block;
    padding: 2px 8px;
    border-radius: 999px;
    font-size: 11px;
    font-weight: 600;
    letter-spacing: 0.03em;
  }
  .badge-RUNNING { background: rgba(63,185,80,0.15); color: var(--running); }
  .badge-STALE   { background: rgba(210,153,34,0.15); color: var(--stale); }
  .badge-DONE    { background: rgba(88,166,255,0.15); color: var(--done); }
  .badge-FAILED  { background: rgba(248,81,73,0.15); color: var(--failed); }
  .empty {
    color: var(--muted);
    padding: 32px 0;
    text-align: center;
    font-size: 13px;
  }
  .dot {
    display: inline-block;
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--running);
    margin-right: 6px;
    animation: pulse 1.5s ease-in-out infinite;
  }
  @keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.3; } }
</style>
</head>
<body>
  <h1>heartbeat_wrap dashboard</h1>
  <div class="sub" id="sub">
    <span class="dot"></span>watching <code id="registry-dir"></code> - refreshes every 2s
  </div>
  <div id="content"></div>

<script>
async function refresh() {
  let res;
  try {
    res = await fetch('/api/jobs');
  } catch (e) {
    return;
  }
  if (!res.ok) return;
  const data = await res.json();
  document.getElementById('registry-dir').textContent = data.registry_dir;
  const jobs = data.jobs;
  const content = document.getElementById('content');

  if (jobs.length === 0) {
    content.innerHTML = '<div class="empty">No jobs found. Run something with heartbeat_wrap.sh to see it here.</div>';
    return;
  }

  let rows = '';
  for (const j of jobs) {
    const badge = `<span class="badge badge-${j.state}">${j.state}</span>`;
    const exit = (j.exit_code === null || j.exit_code === undefined) ? '-' : j.exit_code;
    rows += `<tr>
      <td>${badge}</td>
      <td>${j.label ? escapeHtml(j.label) : '<span style="color:#8a8f98">(none)</span>'}</td>
      <td><code>${escapeHtml(j.command)}</code></td>
      <td>${j.host ? escapeHtml(j.host) : ''}</td>
      <td>${j.pid}${j.pid_alive ? '' : ' <span style="color:#8a8f98">(exited)</span>'}</td>
      <td>${j.elapsed_fmt}</td>
      <td>${exit}</td>
    </tr>`;
  }

  content.innerHTML = `<table>
    <thead><tr>
      <th>State</th><th>Label</th><th>Command</th><th>Host</th><th>PID</th><th>Elapsed</th><th>Exit</th>
    </tr></thead>
    <tbody>${rows}</tbody>
  </table>`;
}

function escapeHtml(s) {
  const div = document.createElement('div');
  div.textContent = s;
  return div.innerHTML;
}

refresh();
setInterval(refresh, 2000);
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    registry_dir = DEFAULT_REGISTRY_DIR

    def log_message(self, fmt, *args):
        # Keep the terminal quiet; this is a local dev tool, not a server
        # that needs an access log.
        pass

    def _send_json(self, obj, status=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, body: str, status=200):
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/" or self.path.startswith("/index.htm"):
            self._send_html(PAGE_TEMPLATE)
            return
        if self.path.startswith("/api/jobs"):
            jobs = load_jobs(self.registry_dir)
            for j in jobs:
                j["elapsed_fmt"] = format_elapsed(j["elapsed_seconds"])
            self._send_json({
                "registry_dir": self.registry_dir,
                "server_time": time.time(),
                "jobs": jobs,
            })
            return
        self._send_html("<h1>404</h1>", status=404)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                         help=f"Port to serve on (default: {DEFAULT_PORT})")
    parser.add_argument("--registry-dir", default=DEFAULT_REGISTRY_DIR,
                         help=f"Directory heartbeat_wrap.sh writes job_*.json to (default: {DEFAULT_REGISTRY_DIR})")
    args = parser.parse_args()

    Handler.registry_dir = args.registry_dir

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"heartbeat_wrap dashboard running at http://localhost:{args.port}/")
    print(f"Watching registry dir: {args.registry_dir}")
    print("Press Ctrl-C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping.")
    finally:
        server.server_close()


if __name__ == "__main__":
    sys.exit(main())
