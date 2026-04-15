# 0007 — Commit script does not auto-init repositories

* Status: accepted
* Date: 2026-04-15

## Context and problem statement

`stenogit-commit` could call `git init` if the target directory
is not yet a git repo. This sounds friendly but introduces problems:

- It would have to also set git identity (otherwise the commit fails),
  which is a CLI-level concern.
- A typo in `DIR` would silently create a new git repo in an unintended
  place.
- It mixes "operate on a repo" with "create a repo" in a script that
  runs unattended on a timer.

## Decision

The commit script refuses to run on a directory that is not already a
git repo. It exits non-zero with a clear error pointing the user at
`stenogit add`.

Repository initialization and identity setup are the CLI's `add`
command's responsibility.

## Consequences

- The commit script is small, predictable, and idempotent.
- Accidental repo creation is impossible from a misconfigured timer.
- Tests can assert "non-git dir → error" without contortions.
- The CLI is the only place `git init` lives → easier to test and
  reason about.
- `stenogit add` may be enhanced to detect and skip init for an
  already-existing git repo, but the commit script never touches it.
