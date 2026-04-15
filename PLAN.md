# Stenogit — Build Plan

## Goal

A daemon-less tool that monitors arbitrary directories and auto-commits
changes to git, fully unattended. Each tracked directory can be triggered
either by inotify (real-time) or by a systemd timer (scheduled). Multi-instance,
package-friendly (eventual `.deb`), no logic in systemd unit files.

## Architecture overview

Three executables plus a thin layer of systemd wiring:

1. **`stenogit-commit`** — pure shell script. Reads env vars (`DIR`,
   `INSTANCE`, `MESSAGE_TEMPLATE`), stages all changes in `DIR`, commits
   if anything is staged, expanding placeholders in the message template.
   Idempotent: a no-op when there are no changes. Refuses to operate on a
   non-git directory (no auto-init).

2. **`stenogit-watch`** — pure shell script. Runs `inotifywait -mr`
   on `DIR`, debounces bursts (waits for a quiet window of `DEBOUNCE`
   seconds), then invokes `stenogit-commit` as a subprocess. Reads
   the same env vars plus `DEBOUNCE`.

3. **`stenogit`** — CLI that hides systemd from end users.
   Subcommands:
   - `add <name> <dir> [--schedule <interval> | --watch] [--message <tpl>] [--git-name <n>] [--git-email <e>] [--debounce <s>]`
   - `remove <name>`
   - `list`
   - `status <name>`

   `add` initialises the git repo in `<dir>`, sets the local git identity,
   writes `~/.config/stenogit/<name>.conf`, optionally writes a
   systemd timer drop-in for the schedule, and enables the appropriate
   systemd user unit.

Systemd wires the components. Unit files contain only `Type=`,
`EnvironmentFile=`, `Environment=`, `ExecStart=` — no logic.

## Components — systemd units

- `stenogit@.service` — `Type=oneshot`. ExecStart calls
  `stenogit-commit`. `EnvironmentFile=%h/.config/stenogit/%i.conf`.
  `Environment=INSTANCE=%i`.
- `stenogit@.timer` — default schedule (e.g. `OnUnitActiveSec=15min`).
  Per-instance schedule overridden via drop-in
  (`stenogit@<name>.timer.d/schedule.conf`).
- `stenogit-watch@.service` — long-running. ExecStart calls
  `stenogit-watch`. Same env-file pattern. `Restart=on-failure`.

## Repository layout

```
bin/
  stenogit
  stenogit-commit
  stenogit-watch
systemd/
  stenogit@.service.in
  stenogit@.timer
  stenogit-watch@.service.in
tests/
  test_helper.bash
  test_commit.bats
  test_watch.bats
  test_cli.bats
  fixtures/
    fake-systemctl
docs/
  systemd-crash-course.md
  parameterization.md
  deb-packaging-notes.md
  adr/
    0001-...
examples/
  example.conf
Dockerfile
Makefile
PLAN.md
```

`*.in` unit files contain `@BINDIR@` placeholders rendered by `make build`
to `build/systemd/`. This lets the same unit work at any `PREFIX`.

## Install layout (filesystem)

```
$PREFIX/bin/stenogit
$PREFIX/bin/stenogit-commit
$PREFIX/bin/stenogit-watch
$PREFIX/lib/systemd/user/stenogit@.service
$PREFIX/lib/systemd/user/stenogit@.timer
$PREFIX/lib/systemd/user/stenogit-watch@.service
$PREFIX/share/stenogit/example.conf
```

`PREFIX` defaults to `/usr/local` (ad-hoc install). The future `.deb`
overrides to `PREFIX=/usr`. Per-user state lives in
`$XDG_CONFIG_HOME/stenogit/` (i.e. `~/.config/stenogit/`),
never inside `$PREFIX`.

## Build system — Makefile

Variables:
- `PREFIX ?= /usr/local`
- `DESTDIR ?=`
- `CONTAINER ?= podman`
- `IMAGE ?= stenogit-test`

Targets:
- `build` — render `systemd/*.in` → `build/systemd/*` with `@BINDIR@`
  substituted to `$(PREFIX)/bin`.
- `test` — build the test container image, run `bats tests/` inside it
  with the source mounted at `/src`.
- `install` — copy `bin/`, `build/systemd/`, examples to
  `$(DESTDIR)$(PREFIX)/...`.
- `uninstall` — reverse of install.
- `clean` — remove `build/`.

## Testing strategy

All tests run inside a podman container so the host filesystem is
untouched and `bats` does not need to be installed locally.

`Dockerfile`: `debian:stable-slim` + `bats git inotify-tools make
ca-certificates`. Source is mounted at `/src` at run time, not baked in,
so the edit-test cycle is fast.

### `test_commit.bats`
- Errors when `DIR` is unset.
- Errors when target dir does not exist.
- Errors when target is not a git repo (no auto-init).
- No-op when there are no changes (no commit produced, exit 0).
- Commits added files.
- Commits modified files.
- Commits deleted files.
- Default message template applied if `MESSAGE_TEMPLATE` unset.
- Expands `{date}`, `{count}`, `{host}`, `{name}` placeholders.
- Multiple placeholders in one template.
- `{count}` is correct for multi-file commits.
- Initial commit on a fresh repo with files.

### `test_watch.bats`
- Single event triggers exactly one commit invocation.
- Burst of N events within debounce window triggers exactly one commit.
- Two events separated by more than the window trigger two commits.
- The actual `inotifywait` wiring is not unit-tested — the debounce
  loop is tested in isolation by feeding lines into stdin and observing
  invocations of a fake commit binary set via `STENOGIT_COMMIT`.

### `test_cli.bats`
- `add` rejects names containing slashes or shell metachars.
- `add` errors when target directory does not exist.
- `add` initialises a git repo in target.
- `add` sets `user.name` / `user.email` in the target repo from
  `--git-name` / `--git-email`.
- `add` writes the conf file with expected keys.
- `add --schedule 5min` writes a timer drop-in containing
  `OnUnitActiveSec=5min`.
- `add --watch` enables `stenogit-watch@<name>.service`.
- `add` (default) enables `stenogit@<name>.timer`.
- `remove` deletes the conf file.
- `remove` disables the systemd unit.
- `list` shows configured instances.
- `list` shows nothing when none are configured.

`systemctl` is mocked via `tests/fixtures/fake-systemctl` placed earlier
in `PATH`, so the CLI tests touch nothing on the real system.

## Test-friendly script structure

Each script is structured so functions can be tested in isolation:

```bash
#!/usr/bin/env bash
set -euo pipefail

# All functions defined here.
do_thing() { ... }
main() { ... }

# Only run main when executed, not when sourced by bats.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

Bats sources the script and calls individual functions or `main` directly.

## Future work

- `debian/` directory with `control`, `rules`, `changelog` for `.deb`.
- `stenogit status <name>` summarising last commit, current trigger,
  last error from journal.
- Optional GPG-signing per instance (set in repo config at `add` time).

## Open questions

- Should `add` accept an existing git repo and skip the `git init` step,
  or always require an empty/non-git directory? Lean toward: detect and
  skip init if already a repo, but still set identity if missing.
- Default timer schedule: 15 min seems reasonable. Document as overridable.
- Should `remove` also offer a `--purge` that deletes the git repo and
  all commits? Probably no — too destructive for a CLI default.
