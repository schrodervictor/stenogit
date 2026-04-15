# 0001 — Support both inotify and scheduled triggers

* Status: accepted
* Date: 2026-04-15

## Context and problem statement

The config tracker watches a directory and commits changes to git
automatically. The trigger mechanism — *when* a commit fires — has a
real impact on how well the tool fits a given directory.

- A live config file (e.g. `/etc/nginx`) wants immediate capture so an
  operator can see "what was on disk at the moment of the change."
- A directory that changes in bursts, or only when a script runs, is
  better served by a periodic snapshot — inotify would burn wakeups for
  no benefit.

A single-mode tool forces the wrong trade-off on at least one of these.

## Decision drivers

- Per-directory choice; no global "use inotify or schedule" knob.
- Identical commit logic regardless of trigger.
- No new daemon to maintain; lean on systemd primitives.

## Considered options

1. **inotify only** — accurate, low latency, but every directory pays
   the cost of an always-on watcher process.
2. **timer only** — cheap, simple, but can lose intermediate states
   between ticks.
3. **Both, selectable per instance** — one shared commit script, two
   trigger families.

## Decision

Option 3. Both triggers supported; the user picks per instance via the
CLI.

## Consequences

- Two systemd unit families:
  - `config-tracker@.timer` (scheduled)
  - `config-tracker-watch@.service` (inotify, long-running)
- A single `config-tracker-commit` script reused by both.
- The CLI accepts either `--schedule <interval>` or `--watch` at `add`
  time and enables the corresponding unit.
- If both are accidentally enabled for the same instance they do not
  conflict — the commit script is idempotent — but it wastes wakeups.
  Worth noting in the README, not enforcing.
