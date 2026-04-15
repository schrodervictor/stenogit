# 0004 — Logic in scripts, wiring in systemd units

* Status: accepted
* Date: 2026-04-15

## Context and problem statement

Systemd unit files are not test-friendly. There is no way to mock their
environment, run them in isolation, or assert on their behavior cheaply.
Bats, by contrast, tests shell scripts well.

If business logic creeps into unit files (`ExecStartPre=` chains,
inline `bash -c`, conditionals via `ConditionX=`), the project becomes
untestable in any meaningful sense.

## Decision

All logic lives in shell scripts under `bin/`. Systemd unit files
contain only:

- `Type=`
- `EnvironmentFile=`
- `Environment=` (e.g. `INSTANCE=%i`)
- `ExecStart=` (a single absolute path to one of our scripts)
- `Restart=`, `WantedBy=`, and similar pure-wiring directives

Anything more complex than that in a unit file is a bug to fix.

Scripts are written so functions can be tested in isolation. The
`main`-only-when-executed pattern is used:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

## Consequences

- Bats tests cover everything that matters.
- Unit files are short and review-friendly.
- Re-targeting the tool (e.g. to OpenRC, or to a long-running daemon
  process model) only touches the wiring layer.
- Scripts must be invocable standalone with env vars set — which they
  already need to be, for tests.
