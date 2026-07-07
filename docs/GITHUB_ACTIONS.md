# Using heartbeat-wrap in GitHub Actions

This repo ships a self-contained composite GitHub Action (`action.yml` at
the repo root) that wraps any CI step's command with `heartbeat_wrap.sh` —
no vendoring, no extra checkout step, no separate install. Point `uses:`
at this repo and it works.

This is the "generic CI-plugin form" referenced in the main
[README's roadmap section](../README.md#roadmap--pro-tier-ideas) — unlike
the [MCP server](../README.md) (which lets an *AI coding agent* run a
background job and poll it non-blockingly), this action is for wrapping a
step inside a **CI workflow you already have**, so a slow-but-fine step
never gets mistaken for a hung one in your Actions log, and you can
optionally get pinged (Slack/Discord/generic webhook) the moment it
finishes or looks stuck.

## Quick start

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run the slow thing, with a heartbeat every 30s
        uses: matthewblipscomb-creator/heartbeat-wrap@v2   # tagged release, see ../CHANGELOG.md
        with:
          command: './run_migrations.sh'
          label: 'migrations'
```

That's it — the step's log will print a heartbeat line every 30 seconds
while `./run_migrations.sh` runs, so anyone watching the Actions log (or
debugging a slow run later) can immediately tell "still working" from
"this has been silent way too long."

## Inputs

All inputs are optional except `command`. See `action.yml` for the full,
authoritative list with descriptions — this is a task-oriented summary of
the most useful ones:

| Input | Default | When to use it |
|---|---|---|
| `command` | *(required)* | The shell command to run (via `bash -c`) |
| `interval` | `30` | How often (seconds) to print a heartbeat line |
| `label` | `ci` | Tag shown in every heartbeat line; also keys `--history-compare` |
| `immediate` | `true` | Print the first heartbeat right away instead of waiting a full interval |
| `stuck-detect` | `false` | Turn on CPU-idle stuck-detection heuristic — see [caveats](#stuck-detect-caveats-in-ci) below |
| `stuck-threshold` | `3` | Consecutive idle beats before a stuck warning fires |
| `webhook` | *(none)* | POST a JSON payload here when the step finishes (or on stuck warning, with `webhook-on-stuck: true`) |
| `webhook-format` | `generic` | `generic`, `slack`, or `discord` payload shape |
| `webhook-on-stuck` | `false` | Also fire the webhook the moment a stuck warning triggers |
| `fail-on-stuck` | `false` | See [caveat](#fail-on-stuck-caveat) below before enabling |
| `stuck-kill` | `false` | ⚠️ Actually terminates the wrapped step's process on a stuck-heuristic match instead of only warning — see the risk warning in the main [README](../README.md). Implies `stuck-detect` |
| `lint-strict` | `false` | Statically check `command` for unbalanced quotes / unterminated heredocs before running it, and fail the step immediately if anything is flagged. Most useful when `command` is built dynamically |
| `history` / `history-compare` | `false` | See [history across ephemeral runners](#history-across-ephemeral-runners) below |
| `extra-args` | *(none)* | Any other raw `heartbeat_wrap.sh` flag not covered above (e.g. `--fun`) |

## Outputs

| Output | Description |
|---|---|
| `exit-code` | Exit code of the wrapped command |
| `stuck-detected` | `"true"` if a stuck warning ever fired during the run, else `"false"` |

```yaml
      - name: Run with an id so we can read its outputs
        id: mystep
        uses: matthewblipscomb-creator/heartbeat-wrap@v2
        with:
          command: './slow_script.sh'
          stuck-detect: 'true'

      - name: React to a stuck warning
        if: steps.mystep.outputs.stuck-detected == 'true'
        run: echo "::warning::slow_script.sh looked stuck at some point - worth a look."
```

## Recipes

### Ping Slack the moment a step finishes

```yaml
      - uses: matthewblipscomb-creator/heartbeat-wrap@v2
        with:
          command: './deploy.sh'
          webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
          webhook-format: 'slack'
```

### Ping Slack immediately if a step looks stuck, without waiting for it to finish

```yaml
      - uses: matthewblipscomb-creator/heartbeat-wrap@v2
        with:
          command: './long_running_build.sh'
          interval: '60'
          stuck-detect: 'true'
          stuck-threshold: '3'
          webhook: ${{ secrets.SLACK_WEBHOOK_URL }}
          webhook-format: 'slack'
          webhook-on-stuck: 'true'
```

### Pass through any flag not covered by a dedicated input

```yaml
      - uses: matthewblipscomb-creator/heartbeat-wrap@v2
        with:
          command: './backup.sh'
          extra-args: '--fun --message "backing up, hang tight"'
```

## Caveats specific to CI (please read before relying on these)

### `stuck-detect` caveats in CI

The stuck-detection heuristic watches the wrapped process's own CPU time
via `ps`. This works exactly the same way in a GitHub Actions runner as
it does locally, **but** two things are worth knowing:

- A command that's legitimately waiting on slow network I/O (a big
  `docker pull`, a slow external API call, a network-mounted dependency
  cache) can look "stuck" by this heuristic even though it's perfectly
  healthy — that's why it only ever *warns*, never kills anything, in
  both the local script and this action.
- The `stuck-detect-demo` job in `.github/workflows/example.yml`
  deliberately uses a plain `sleep` command specifically because `sleep`
  reports ~0 CPU time throughout — it's a reliable way to confirm the
  heuristic itself fires correctly, but it is *not* representative of a
  real build step (a real hang and a real slow-but-healthy step both
  need to be judged in context, not just from this one signal).

### `fail-on-stuck` caveat

`fail-on-stuck: true` cannot pre-emptively kill a step that's still
running — GitHub Actions composite action steps don't get an
out-of-band way to interrupt a `run:` block mid-execution from another
part of the same step. What it actually does: if a stuck warning fired
*and* the wrapped command still went on to exit `0` on its own, the
action step fails anyway at that point, so the overall job (and any
required-check gating on it) reflects that something looked off during
the run even though the command technically succeeded. If you want an
actual hard timeout that kills a hung step, use the job/step-level
[`timeout-minutes`](https://docs.github.com/en/actions/using-jobs/setting-a-timeout-for-a-job)
GitHub Actions setting — `fail-on-stuck` is a complementary signal, not
a replacement for that.

### History across ephemeral runners

GitHub-hosted runners are torn down after every job, so
`~/.heartbeat_wrap/history.db` does **not** persist between workflow runs
by default — `history-compare` will always report "not enough history
yet" unless you separately persist and restore that file yourself, e.g.:

```yaml
      - uses: actions/cache@v4
        with:
          path: ~/.heartbeat_wrap/history.db
          key: heartbeat-wrap-history-${{ github.job }}
          restore-keys: heartbeat-wrap-history-

      - uses: matthewblipscomb-creator/heartbeat-wrap@v2
        with:
          command: './run_migrations.sh'
          label: 'migrations'
          history-compare: 'true'
```

Self-hosted runners that reuse the same machine across runs don't need
this — the history DB just accumulates naturally in `~/.heartbeat_wrap/`
on that machine like it would on a laptop.

## Local (non-CI) usage

If you landed here but actually want to run `heartbeat_wrap.sh` directly
in a terminal (not inside a GitHub Actions workflow), see the main
[README.md](../README.md) instead — this document is specifically about
the GitHub Action wrapper.

## Testing this action itself

`.github/workflows/example.yml` in this repo is a runnable, living
example (not just documentation) with three jobs: a plain quick command,
a deliberate stuck-detect sanity check (using `sleep`, see caveat above),
and an opt-in webhook demo that only runs once a
`HEARTBEAT_WRAP_DEMO_WEBHOOK_URL` repo variable is configured. Trigger it
manually via the **Run workflow** button (Actions tab → "heartbeat-wrap
example" → *Run workflow*), or it runs automatically on any push that
touches `action.yml`, `heartbeat_wrap.sh`, or the workflow file itself.

Note: this example workflow has not yet been run for real on GitHub's
runners as of when this doc was written (no `git push` has happened yet
in this session) — treat it as "should work, written carefully against
the documented composite-action semantics" rather than "confirmed green"
until its first real run. Please open an issue if it doesn't behave as
described.
