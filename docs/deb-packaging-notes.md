# Systemd and Debian package dependencies

Reference notes from the design discussion. Preserved instructional
material; not a decision document.

## Systemd does not manage package dependencies

`Requires=` and `After=` in systemd unit files are about *unit*
dependencies (other services, mounts, targets), not *package*
dependencies. Systemd has no concept of "make sure git is installed
before running this unit."

A unit can guard itself at runtime with conditions:

```ini
[Unit]
ConditionPathExists=/usr/bin/git
ConditionPathExists=/usr/bin/inotifywait
```

…but that is a runtime guard, not dependency management. If the
condition fails, the unit silently skips. Useful for graceful
degradation, not for ensuring tools exist.

## Debian: `debian/control` is the canonical place

```
Package: config-tracker
Section: utils
Architecture: all
Depends: git, inotify-tools, systemd, bash (>= 4)
Recommends: bats
Description: Auto-commit changes in arbitrary directories to git
```

`apt` resolves `Depends:` at install. `Recommends:` is installed by
default but skippable.

## `dh_installsystemd`

Debhelper's `dh_installsystemd` (called automatically by `dh`)
auto-installs `*.service`, `*.timer`, and `*.path` files placed in
`debian/` or in the package's normal install layout. It also runs
`daemon-reload` on install/upgrade and handles enable/disable on
package operations.

For templated units this still works — instances are user-managed, so
the package only ships the templates themselves.

## FHS implications for unit files

If a `.deb` may install the same units as an ad-hoc install, the
`ExecStart=` paths must not assume `~/.local` or `%h/.local`. They
must be absolute under `$PREFIX`:

```
ExecStart=/usr/bin/config-tracker-commit         # .deb (PREFIX=/usr)
ExecStart=/usr/local/bin/config-tracker-commit   # ad-hoc (PREFIX=/usr/local)
```

Hence the `*.in` template files with `@BINDIR@` substituted at build
time by the Makefile.

## Build scaffolding sketch (for later)

A minimal `.deb` build wraps the existing Makefile:

```
debian/
  changelog
  control
  rules        # invokes `make install PREFIX=/usr DESTDIR=…`
  install      # which files go to which package paths
  compat
```

`debian/rules` is itself a Makefile and can be three lines:

```makefile
#!/usr/bin/make -f
%:
	dh $@
override_dh_auto_install:
	$(MAKE) install PREFIX=/usr DESTDIR=$(CURDIR)/debian/tmp
```

Dependencies go in `debian/control`, file mapping in `debian/install`,
and the existing Makefile does the heavy lifting. Out of scope until
the core tool is working.
