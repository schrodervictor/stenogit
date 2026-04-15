# 0005 — Tests run in a container (podman)

* Status: accepted
* Date: 2026-04-15

## Context and problem statement

The bats test suite creates git repos, writes conf files, and invokes
a mocked systemctl. A test bug or a stray path could overwrite real
state in the user's `~/.config/config-tracker/` or stomp on a real git
repo. Additionally, the user does not want to install bats or
inotify-tools on the host just to run tests.

## Decision drivers

- Host filesystem must be safe from test mistakes.
- No required host packages beyond a container runtime.
- Reproducible across machines and CI.

## Considered options

1. **Run tests on the host with overridable paths** (`HOME=$tmp`,
   `XDG_CONFIG_HOME=$tmp/config`, mocked systemctl). Works but
   relies on the test author getting every override right, every time.
2. **Run tests in an ephemeral container** with the source mounted as
   a volume.

## Decision

Option 2. A `Dockerfile` (compatible with podman) provides
`debian:stable-slim` plus `bats git inotify-tools make
ca-certificates`. `make test` builds the image, then runs `bats tests/`
inside, with the working tree mounted at `/src`.

The container runtime is abstracted via `CONTAINER ?= podman` in the
Makefile so docker users can override with `make CONTAINER=docker test`.

## Consequences

- A `Dockerfile` is part of the repo.
- One-time image build cost (cached after that).
- The test author still uses path overrides inside the container, but
  any bug there is bounded by the container's ephemeral filesystem.
- CI (when added) reuses the same image build.
- Source is mounted at run time, not baked in, so the edit-test cycle
  is fast.
