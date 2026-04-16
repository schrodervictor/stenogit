# 0008 - Watch script invokes commit script as a subprocess

* Status: accepted
* Date: 2026-04-15

## Context and problem statement

`stenogit-watch` is a long-running process running an
`inotifywait -mr` loop with debouncing. When the debounce window
expires, it needs to trigger a commit. There are three plausible ways
to do this.

## Considered options

1. **Subprocess**: exec `stenogit-commit` directly, with the
   same env vars in scope. Simple, fully testable.
2. **Source the commit script and call its `main`**: slightly faster,
   but couples the two scripts and complicates testing of the watch
   loop in isolation.
3. **`systemctl --user start stenogit@<name>.service`**: most
   systemd-pure, logs land in the right journal unit, but couples the
   watch script to systemd at runtime (cannot be tested or run outside
   of systemd) and adds latency per fire.

## Decision

Option 1. The watch script invokes a `STENOGIT_COMMIT`
command (defaults to `stenogit-commit` on `PATH`), so tests can
substitute a fake to observe invocations.

## Consequences

- Two processes per fire (acceptable).
- Logs from watch-triggered commits land in the watch service's journal,
  not the timer service's.
- The debounce loop can be tested in isolation by feeding lines into
  stdin and observing calls to the fake binary.
- No runtime systemd dependency for the watch script itself, which
  means it can also be run by hand for debugging.
