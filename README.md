# Stenogit

*Like a stenographer for your filesystem: sits quietly in the corner,
writes down everything that happens, never interrupts.*

Auto-commit changes in arbitrary directories to git, fully unattended.
Each tracked directory gets its own git repository and can be triggered
by inotify (real-time) or by a systemd timer (scheduled).

## Quick start

```sh
# Track /etc/nginx with a 10-minute timer (system scope, requires root)
sudo stenogit add nginx /etc/nginx --schedule 10min

# Track ~/dotfiles with inotify (user scope, no root needed)
stenogit add --user dotfiles ~/dotfiles --watch

# List all tracked instances
stenogit list

# Stop tracking
sudo stenogit remove nginx
stenogit remove dotfiles --user
```

## How it works

Three shell scripts, wired together by systemd:

- **`stenogit-commit`** stages all changes in a directory and commits
  with a templated message. Idempotent: no-op when nothing changed.
- **`stenogit-watch`** runs `inotifywait` on the directory, debounces
  bursts, then calls `stenogit-commit`. A max-wait ceiling (default 60s)
  prevents unbounded delays under sustained churn.
- **`stenogit`** is the CLI. It initializes the git repo, writes the
  config, and enables the right systemd unit.

All logic lives in the scripts. Systemd unit files contain only wiring
(`Type=`, `EnvironmentFile=`, `ExecStart=`).

## Install

```sh
make build
sudo make install        # installs to /usr/local by default
```

Override the prefix for packaging:

```sh
make install PREFIX=/usr DESTDIR=debian/tmp
```

### Dependencies

`bash` (>= 4), `git`, `inotify-tools` (for `--watch` mode), `systemd`.

## Usage

### `stenogit add`

```
stenogit add <name> <dir> [options]

Options:
  --user                    Per-user systemd units (default: system)
  --schedule <interval>     Use a systemd timer (e.g. 10min, 1h)
  --watch                   Use inotify watcher (mutually exclusive with --schedule)
  --message <template>      Commit message template (default: "auto: {date}")
  --debounce <seconds>      Quiet window for --watch (default: 5)
  --max-wait <seconds>      Max time before forced commit (default: 60; 0 disables)
  --git-name <name>         Git user.name for the tracked repo
  --git-email <email>       Git user.email for the tracked repo
```

System scope (default) requires root and stores config in
`/etc/stenogit/`. User scope (`--user`) stores config in
`~/.config/stenogit/` and requires `loginctl enable-linger` for
unattended operation.

### `stenogit remove`

```
stenogit remove <name> [--user]
```

Without `--user`, auto-detects scope from where the config file lives.

### `stenogit list`

Lists all tracked instances with their scope (system or user).

### Message template placeholders

The commit message supports these placeholders:

- `{date}`: ISO-8601 timestamp
- `{count}`: number of staged files
- `{host}`: hostname
- `{name}`: instance name

Example: `--message "auto: {name} {date} ({count} files)"`

## Configuration

Each instance has a conf file (`/etc/stenogit/<name>.conf` or
`~/.config/stenogit/<name>.conf`) with:

```sh
DIR=/etc/nginx
MESSAGE_TEMPLATE=auto: {date}
DEBOUNCE=5
MAX_WAIT=60
```

Git identity is stored in the tracked repo's `.git/config`, not in
the conf file. Timer schedule overrides use systemd drop-ins.

See [docs/parameterization.md](docs/parameterization.md) for the
full configuration model.

## Debugging

If a service is failing or not committing as expected, see
[docs/debugging.md](docs/debugging.md) for a step-by-step guide
covering `systemctl status`, journal inspection, common exit codes,
and how to test scripts outside systemd.

## Testing

All tests run inside a container (podman by default, docker also
supported) to avoid touching the host filesystem.

### Unit tests

```sh
make test                      # uses podman
make CONTAINER=docker test     # uses docker
```

76 bats tests (`tests/unit/`) cover the commit script, watch debounce
loop (including max-wait ceiling), inotifywait integration (.git
exclusion, nested directories), and the CLI (both system and user scope).

### End-to-end tests

```sh
make test-e2e
```

5 bats tests (`tests/e2e/`) run against real systemd inside a podman
container with systemd as PID 1. These exercise the full lifecycle:
timer mode, schedule drop-ins, watch mode with real inotify, list, and
remove cleanup. Requires podman (not docker, since docker containers
cannot easily run systemd as PID 1).

The e2e target handles the container lifecycle automatically: starts a
systemd container, installs stenogit via `make install PREFIX=/usr`,
runs the test suite, then tears down.

### Linting

```sh
make lint
```

Runs shellcheck against all scripts and the test helper.

### CI

GitHub Actions (`.github/workflows/`) runs unit tests and shellcheck on
every push and pull request to `master`.

## Project structure

```
bin/                           Shell scripts (all logic here)
systemd/system/                System-scope unit templates
systemd/user/                  User-scope unit templates
tests/unit/                    Bats unit tests (hermetic, no systemd)
tests/e2e/                     Bats end-to-end tests (real systemd)
docs/                          Reference docs and ADRs
examples/example.conf          Sample configuration
.github/workflows/             CI configuration
```

## Design decisions

Architectural decisions are recorded in [docs/adr/](docs/adr/):

- [0001](docs/adr/0001-dual-trigger.md) - Dual trigger (inotify + timer)
- [0002](docs/adr/0002-systemd-templated-units.md) - Systemd templated units
- [0003](docs/adr/0003-three-layer-configuration.md) - Three-layer configuration
- [0004](docs/adr/0004-logic-in-scripts.md) - Logic in scripts, wiring in systemd
- [0005](docs/adr/0005-tests-in-container.md) - Tests in a container
- [0006](docs/adr/0006-fhs-layout-and-makefile.md) - FHS layout, Makefile-driven
- [0007](docs/adr/0007-no-auto-init.md) - No auto-init in commit script
- [0008](docs/adr/0008-watch-invokes-commit-subprocess.md) - Watch invokes commit as subprocess
- [0009](docs/adr/0009-system-scope-default.md) - System scope by default
- [0010](docs/adr/0010-debounce-max-wait.md) - Debounce with max-wait ceiling

## License

[MIT](LICENSE)
