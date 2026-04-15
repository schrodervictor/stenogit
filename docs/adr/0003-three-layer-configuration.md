# 0003 — Configuration in three layers

* Status: accepted
* Date: 2026-04-15

## Context and problem statement

An instance has three different kinds of values:

1. Runtime knobs the commit script reads each invocation (target dir,
   message template, debounce).
2. Git identity used for commits in the tracked repository.
3. Schedule for the systemd timer.

These have different lifecycles and different natural consumers. A
single bag-of-everything config either duplicates state or fights at
least one of its consumers.

## Decision drivers

- Each value should live where the tool that owns it naturally looks.
- Editing a value with native tools (text editor, `git config`,
  `systemctl edit`) should Just Work.
- The CLI exists to hide the layering — users do not need to know it.

## Considered options

1. **Single YAML/TOML per instance** with everything inside, plus glue
   to apply the values into git config and systemd at `add` time.
2. **Three layers**, each value stored where its consumer reads it
   directly.

## Decision

Option 2. Three layers:

| Layer                | Where                                                                     | Holds                                  |
|----------------------|---------------------------------------------------------------------------|----------------------------------------|
| Env file             | `~/.config/stenogit/<name>.conf`                                    | `DIR`, `MESSAGE_TEMPLATE`, `DEBOUNCE`  |
| Per-repo git config  | `<DIR>/.git/config`                                                       | `user.name`, `user.email`, GPG knobs   |
| Systemd timer drop-in| `~/.config/systemd/user/stenogit@<name>.timer.d/schedule.conf`      | `OnUnitActiveSec=`                     |

## Consequences

- The commit script does not need to know about git identity at runtime
  — the repo already has it.
- Schedule changes do not require touching the conf file; conf changes
  do not require touching systemd.
- Three places to look when something is off — mitigated by
  `stenogit status` (future) and by the CLI being the canonical
  edit interface.
- Bats tests exercise each layer in isolation.
- See `docs/parameterization.md` for the user-facing how-to.
