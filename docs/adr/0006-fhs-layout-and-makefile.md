# 0006 — FHS install layout, Makefile-driven

* Status: accepted
* Date: 2026-04-15

## Context and problem statement

There are two install audiences:

1. Ad-hoc users (developers, non-Debian systems) who run
   `sudo make install`.
2. Future `.deb` packaging, where Debian's toolchain expects a
   well-behaved Makefile and FHS-compliant paths.

Both should produce a layout systemd recognises and that does not
surprise sysadmins.

## Decision drivers

- Standard FHS paths.
- Same Makefile serves both audiences.
- We ship templated *user* units, not system units; they live in
  `$PREFIX/lib/systemd/user/`.
- Per-user runtime state never lives inside `$PREFIX`.

## Decision

A Makefile drives everything with these variables:

- `PREFIX ?= /usr/local` — ad-hoc default. `.deb` overrides to `/usr`.
- `DESTDIR ?=` — staging dir for `.deb` build.
- `CONTAINER ?= podman` — for `make test`.

Install layout:

```
$PREFIX/bin/config-tracker
$PREFIX/bin/config-tracker-commit
$PREFIX/bin/config-tracker-watch
$PREFIX/lib/systemd/user/config-tracker@.service
$PREFIX/lib/systemd/user/config-tracker@.timer
$PREFIX/lib/systemd/user/config-tracker-watch@.service
$PREFIX/share/config-tracker/example.conf
```

Per-user state lives in `$XDG_CONFIG_HOME/config-tracker/` (i.e.
`~/.config/config-tracker/`).

## Consequences

- No `~/.local`-flavored install path — the project does not pretend
  to be user-installable without root.
- Local installs require `sudo make install` (or a user-owned PREFIX
  that the user sets explicitly).
- Unit files need `PREFIX` baked in: stored as `*.in` templates with
  `@BINDIR@` placeholders, rendered by `make build`.
- `.deb` packaging is a thin wrapper:
  `make install PREFIX=/usr DESTDIR=debian/tmp` plus `debian/control`
  listing dependencies.
- See `docs/deb-packaging-notes.md` for the packaging sketch.
