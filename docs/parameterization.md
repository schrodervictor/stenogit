# Parameterization layers

Reference for how a config-tracker instance is configured. Preserved
instructional material — see ADR-0003 for the decision and rationale.

There are three distinct kinds of parameters, each living where the tool
that consumes it naturally looks. The CLI hides all three behind one
`config-tracker add` command.

## 1. Per-instance conf file (most things)

`~/.config/config-tracker/<name>.conf` — a flat KEY=VALUE file loaded by
the systemd unit via `EnvironmentFile=%h/.config/config-tracker/%i.conf`.
The script reads env vars with defaults:

```sh
DIR="${DIR:?DIR is required}"
MESSAGE_TEMPLATE="${MESSAGE_TEMPLATE:-auto: {date}}"
DEBOUNCE="${DEBOUNCE:-5}"
```

Good for: target dir, message template, debounce, and any future runtime
knobs you might want to tweak per instance.

## 2. Per-repo git config (git identity)

Do **not** pass `user.name` / `user.email` through env. Set them once at
init time with:

```sh
git -C "$DIR" config user.name "Config Tracker"
git -C "$DIR" config user.email "tracker@localhost"
```

They live in the repo's `.git/config` and travel with it. The conf file
holds `GIT_USER_NAME=` / `GIT_USER_EMAIL=` only as inputs to
`config-tracker add`, which writes them into the repo and then forgets
them.

The same applies to any other git knob: `commit.gpgsign=false`,
`core.autocrlf`, etc. — set on the repo, not the runtime env.

## 3. Template defaults + drop-ins (schedule)

Schedule is not really a script parameter — it is a systemd thing.
Default lives in `config-tracker@.timer`, override per instance via
drop-in:

```
~/.config/systemd/user/config-tracker@<name>.timer.d/schedule.conf
```

```ini
[Timer]
OnUnitActiveSec=
OnUnitActiveSec=10min
```

Keep schedule out of the conf file so there is one source of truth.

## Message template expansion

A tiny placeholder syntax is expanded by the script before committing:

```
MESSAGE_TEMPLATE="auto: {date} ({count} files)"
```

```sh
msg="$MESSAGE_TEMPLATE"
msg="${msg//\{date\}/$(date -Iseconds)}"
msg="${msg//\{count\}/$(git diff --cached --name-only | wc -l)}"
msg="${msg//\{host\}/$(hostname)}"
msg="${msg//\{name\}/$INSTANCE}"
git commit -m "$msg"
```

Useful placeholders:
- `{date}` — ISO-8601 timestamp
- `{count}` — number of files staged
- `{host}` — `hostname`
- `{name}` — instance name (from `INSTANCE` env, injected by systemd via
  `Environment=INSTANCE=%i`)

## What `config-tracker add` does

The CLI hides all three layers:

```sh
config-tracker add nginx /etc/nginx \
  --schedule 10min \
  --message "auto: nginx {date}" \
  --git-name "Config Tracker" \
  --git-email "tracker@localhost"
```

Under the hood:
1. `git init` in `/etc/nginx` (skipped if already a repo).
2. `git config user.name/email` in that repo.
3. Write `~/.config/config-tracker/nginx.conf` with `DIR=`,
   `MESSAGE_TEMPLATE=`.
4. If `--schedule`, write the timer drop-in
   `~/.config/systemd/user/config-tracker@nginx.timer.d/schedule.conf`.
5. `systemctl --user daemon-reload`.
6. `systemctl --user enable --now <appropriate-unit>`.

## Why the split

- **Conf file** = runtime knobs the script reads each invocation. Easy
  to edit, no `daemon-reload`.
- **Repo config** = identity / policy that belongs to the repo itself.
  Survives if the directory is moved.
- **Drop-in** = systemd's job, not the script's.

Each value is editable with native tools (text editor, `git config`,
`systemctl edit`). The CLI exists so users do not have to know all three.
