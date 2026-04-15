# Systemd templated units — crash course

Reference for the templated-unit pattern used by config-tracker. This is
not a decision document — it is preserved instructional material so future
sessions can be cleaned without losing context.

## The core idea

A unit file with `@` in the name is a **template**. You never run the
template directly; you run **instances** of it, where the part after `@`
is the instance name.

```
foo@.service        ← template (file on disk)
foo@alice.service   ← instance (alice = instance name)
foo@bob.service     ← another instance, same template
```

One file, many running copies — each parameterized by its instance name.

## Specifiers (the magic %)

Inside the template, `%i` expands to the instance name. Common specifiers:

| Specifier | Means                                       |
|-----------|---------------------------------------------|
| `%i`      | Instance name (`alice`)                     |
| `%I`      | Same, but unescaped (handles `/` etc.)      |
| `%h`      | User's home dir                             |
| `%U`      | User ID                                     |
| `%n`      | Full unit name (`foo@alice.service`)        |

## Minimal example

`~/.config/systemd/user/greet@.service`:

```ini
[Unit]
Description=Greet %i

[Service]
Type=oneshot
ExecStart=/bin/echo "hello %i"
```

Run it:

```sh
systemctl --user start greet@world
journalctl --user -u greet@world   # → "hello world"
```

Same file, different instance: `greet@victor` → "hello victor". No edits.

## Per-instance config

The template stays generic; per-instance data lives in a sidecar file
the script reads. Convention:

```ini
ExecStart=/usr/local/bin/greet-script %i
EnvironmentFile=%h/.config/greet/%i.conf
```

Then `~/.config/greet/world.conf` holds `DIR=/etc`, `DEBOUNCE=5`, etc.
The script reads env vars. Each instance has its own config without
touching the unit file.

## Timers, also templated

`greet@.timer`:

```ini
[Unit]
Description=Run greet for %i

[Timer]
OnUnitActiveSec=5min
Unit=greet@%i.service

[Install]
WantedBy=timers.target
```

`systemctl --user enable --now greet@world.timer` schedules that one
instance.

## Per-instance schedule overrides (drop-ins)

The template has a default schedule, but you can override per instance
with a **drop-in directory**:

```
~/.config/systemd/user/greet@world.timer.d/override.conf
```

```ini
[Timer]
OnUnitActiveSec=
OnUnitActiveSec=30s
```

The empty `OnUnitActiveSec=` clears the inherited value before setting
the new one (otherwise systemd appends to list-typed properties). After
editing, run `systemctl --user daemon-reload`.

## Lifecycle commands

```sh
systemctl --user daemon-reload                      # after editing units
systemctl --user enable --now foo@name.timer        # enable + start
systemctl --user disable --now foo@name.timer       # stop + disable
systemctl --user status foo@name.service
journalctl --user -u foo@name.service -f            # follow logs
systemctl --user list-timers                        # see scheduled units
```

## Gotchas

- **`--user` vs system**: user units live in `~/.config/systemd/user/`
  (or `$PREFIX/lib/systemd/user/` for packaged units) and run as you.
  System units need root and live in `/etc/systemd/system/`. Pick one
  and stick with it; do not mix.

- **User units stop at logout** unless you run
  `loginctl enable-linger $USER` once. For an unattended config tracker
  you almost certainly want lingering on.

- **`daemon-reload` is required** after any unit-file or drop-in change,
  or systemd keeps using the cached version.

- **Instance names with `/`** must be escaped with `systemd-escape`. For
  short names like `dotfiles`, `nginx` this does not come up.

- **`Type=oneshot`** is right for short-lived scripts like the commit
  script — systemd waits for it to finish and tracks success/failure
  correctly. Do not use the default `Type=simple` for short-lived scripts.

## How this maps to config-tracker

- `config-tracker@.service` (oneshot) — runs the commit script, reads
  `~/.config/config-tracker/%i.conf` for `DIR`, `MESSAGE_TEMPLATE`.
- `config-tracker@.timer` — default schedule; per-instance overrides
  via drop-ins written by `config-tracker add --schedule …`.
- `config-tracker-watch@.service` — long-running inotify variant, same
  conf file.
- The `config-tracker` CLI writes the conf, optionally writes the
  drop-in, runs `daemon-reload`, and enables the right unit.
