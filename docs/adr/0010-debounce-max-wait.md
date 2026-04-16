# 0010 - Debounce with max-wait ceiling

* Status: accepted
* Date: 2026-04-16

## Context and problem statement

The watch script debounces filesystem events by resetting a timer on
every new event and committing only after a quiet window (`DEBOUNCE`
seconds of silence). This produces clean, quiescent snapshots but has
an unbounded-delay problem: a directory with sustained churn (log
rotation, continuous builds, frequent writes) may never go silent, so
commits are postponed indefinitely.

Two interpretations of the debounce window exist:

1. **Calm-down window** (current): wait for silence, then commit. Good
   snapshots, unbounded latency.
2. **Accumulate window**: start timer on first event, commit when it
   expires regardless of ongoing activity. Bounded latency, but the
   snapshot may capture a partial state mid-burst.

Neither alone is sufficient for all use cases.

## Decision drivers

- Commits should not be delayed without limit under sustained churn.
- Snapshots should still prefer quiescent states when possible.
- The fix must be simple enough to test with bats (no real inotify needed).
- Backward compatible: existing behavior unchanged when max-wait is
  not reached.

## Considered options

1. **Keep current behavior.** Accept the unbounded delay as a known
   limitation. Users with busy directories use `--schedule` instead.
2. **Switch to accumulate-only.** Replace calm-down with a fixed
   window from first event. Loses the clean-snapshot property.
3. **Combine both: calm-down window + max-wait ceiling.** Keep the
   calm-down debounce, but add an upper bound that forces a commit
   even if events are still flowing.

## Decision

Option 3. The debounce loop tracks two clocks:

- **Debounce clock**: resets on every event. When it expires (silence),
  commit fires. This is the existing behavior.
- **Max-wait clock**: starts when the first event of a burst arrives.
  Never resets within a burst. When it expires, commit fires even if
  events are still arriving.

Commit fires when EITHER clock expires. After each commit, both clocks
are invalidated so the next burst starts fresh.

New environment variable: `MAX_WAIT` (default 60 seconds). Set to 0
to disable the ceiling and restore the previous unbounded behavior.

## Consequences

- Busy directories get commits at most every `MAX_WAIT` seconds,
  even under continuous churn.
- Quiet directories behave exactly as before (debounce expires before
  max-wait).
- The `read -t` inner loop gains a wallclock check. On each iteration,
  the remaining time until max-wait is computed and used to cap the
  `read -t` timeout, so the loop exits promptly when the ceiling hits.
- Two new test cases: sustained churn forces commit at max-wait, and
  the max-wait clock resets after commit (does not bleed into the next
  burst).
- The CLI's `cmd_add` writes `MAX_WAIT` to the conf file alongside
  `DEBOUNCE`, and adds a `--max-wait` option.
