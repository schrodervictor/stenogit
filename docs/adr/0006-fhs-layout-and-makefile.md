# 0006 - FHS install layout, Makefile-driven

* Status: accepted
* Date: 2026-04-15

> **Amended by [ADR-0009](0009-system-scope-default.md) (2026-04-16):**
> System-scope unit templates install to `$PREFIX/lib/systemd/system/`
> instead of `$PREFIX/lib/systemd/user/`. User-scope templates are still
> supported as opt-in and retain the original path. The FHS rationale
> below stands unchanged.

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

- `PREFIX ?= /usr/local`: ad-hoc default. `.deb` overrides to `/usr`.
- `DESTDIR ?=`: staging dir for `.deb` build.
- `CONTAINER ?= podman`: for `make test`.

Install layout:

```
$PREFIX/bin/stenogit
$PREFIX/bin/stenogit-commit
$PREFIX/bin/stenogit-watch
$PREFIX/lib/systemd/user/stenogit@.service
$PREFIX/lib/systemd/user/stenogit@.timer
$PREFIX/lib/systemd/user/stenogit-watch@.service
$PREFIX/share/stenogit/example.conf
```

Per-user state lives in `$XDG_CONFIG_HOME/stenogit/` (i.e.
`~/.config/stenogit/`).

## Consequences

- No `~/.local`-flavored install path. The project does not pretend
  to be user-installable without root.
- Local installs require `sudo make install` (or a user-owned PREFIX
  that the user sets explicitly).
- Unit files need `PREFIX` baked in: stored as `*.in` templates with
  `@BINDIR@` placeholders, rendered by `make build`.
- `.deb` packaging is a thin wrapper:
  `make install PREFIX=/usr DESTDIR=debian/tmp` plus `debian/control`
  listing dependencies.
- See `docs/deb-packaging-notes.md` for the packaging sketch.
