# 0009 — System-scope units by default, user-scope as opt-in

* Status: accepted
* Date: 2026-04-16

## Context and problem statement

The initial implementation wired stenogit as systemd **user** units
(`systemctl --user enable stenogit@<name>.timer`). This works for
personal directories under `$HOME`, but the tool's primary motivating
use case is tracking machine-wide config (`/etc/nginx`, `/etc/postgresql`,
`/boot`), where user-scope creates three concrete problems:

1. **Duplication.** Two users running `stenogit add nginx /etc/nginx`
   would each create an independent git repo under their own identity,
   with their own timers, tracking the same files.
2. **Unattended operation requires lingering.** User units stop at
   logout unless `loginctl enable-linger $USER` is set. The tool's
   explicit goal is fully unattended operation from boot — that's
   adversarial to user-scope defaults.
3. **Convention.** Every distro-shipped systemd automation that is
   an analog of this tool — cron, logrotate, fail2ban, unattended-upgrades,
   and especially **etckeeper** (auto-commits `/etc/` to git on package
   operations) — runs as a system unit. User units are the exception,
   reserved for session-scoped things (pipewire, gnome-keyring, flatpak
   sandboxes, personal backup timers).

Nothing in the commit or watch scripts themselves depends on user scope
— the scripts read `DIR`, `INSTANCE`, `MESSAGE_TEMPLATE` from env and
don't care who's running them. The scope choice is entirely in how
systemd is wired.

## Decision drivers

- Match the conventional default for sysadmin automation tools.
- Work unattended out of the box, without requiring `enable-linger`.
- Keep the personal-directory use case possible, not the default.
- No fork of the scripts: both modes use the same `stenogit-commit`
  and `stenogit-watch`.

## Considered options

1. **System only.** Simplest codebase. Loses the "no-sudo for my
   dotfiles / ~/notes" use case entirely.
2. **User only (current).** What we have. Wrong default for the primary
   use case and requires lingering.
3. **Dual mode, user default, `--system` opt-in.** Matches the
   initial accidental direction; still wrong by convention.
4. **Dual mode, system default, `--user` opt-in.** System units are
   the default; `stenogit add --user <name> <dir>` flips to user scope.

## Decision

Option 4 — dual mode, **system default, `--user` opt-in**.

- `stenogit add <name> <dir>` installs a **system** unit. Requires root.
  Config lives in `/etc/stenogit/<name>.conf`. Drop-ins live in
  `/etc/systemd/system/stenogit@<name>.timer.d/`. Service runs as root
  (simplest for `/etc/*` which is root-owned anyway).
- `stenogit add --user <name> <dir>` installs a **user** unit. No root
  needed. Config lives in `$XDG_CONFIG_HOME/stenogit/<name>.conf`.
  Drop-ins live in `$XDG_CONFIG_HOME/systemd/user/stenogit@<name>.timer.d/`.
  Service runs as the invoking user. Linger is the user's responsibility
  — documented but not enforced.

Mode is stored implicitly in *where* the instance's conf file lives;
`stenogit list` scans both locations and prints scope alongside the name.
`stenogit remove` without a flag checks both, preferring system if both
exist for the same name (unambiguous for `/etc/*` tracking).

The scripts themselves (`stenogit-commit`, `stenogit-watch`) are
unchanged — all the mode awareness lives in the CLI and the install
layout.

## Consequences

- **Default invocation now requires `sudo`.** For the primary use case
  this is correct (writing to `/etc/stenogit/` and `/etc/systemd/system/`
  requires it anyway). The error message when invoked without root
  points at `--user` for personal use.
- **Install layout expands.** The Makefile ships unit templates under
  `$PREFIX/lib/systemd/system/` for system mode, and the CLI places
  copies under `$XDG_CONFIG_HOME/systemd/user/` on demand for user mode
  (the user-mode variant is not pre-installed — it's generated at
  `stenogit add --user` time, or we ship a second static template set,
  TBD in implementation).
- **Linger is no longer required.** System timers fire from boot.
- **`list` reads from two locations.** Must handle either being missing.
- **Tests double for CLI coverage.** The bats suite grows a system-mode
  path; the commit/watch tests are unchanged since the scripts don't
  care.
- **Git identity default changes** to something system-ish
  (`Stenogit <stenogit@$(hostname)>`) rather than per-user. Still
  overridable via `--git-name` / `--git-email`.

## Amendments to prior ADRs

This ADR updates parts of earlier decisions without superseding them:

- **[ADR-0003](0003-three-layer-configuration.md)** — the three-layer
  configuration model still holds. Only the *paths* change in system
  mode: env file at `/etc/stenogit/<name>.conf`, drop-in at
  `/etc/systemd/system/stenogit@<name>.timer.d/schedule.conf`. User mode
  retains the `$XDG_CONFIG_HOME`-based paths from 0003.
- **[ADR-0006](0006-fhs-layout-and-makefile.md)** — FHS discipline
  stands. System-mode unit templates install to
  `$PREFIX/lib/systemd/system/` instead of `$PREFIX/lib/systemd/user/`.
  The Makefile adds that path; the `.deb` sketch is unchanged in spirit.

Unaffected: 0001 (dual trigger), 0002 (templated units), 0005 (tests in
container), 0007 (no auto-init), 0008 (watch invokes commit).
