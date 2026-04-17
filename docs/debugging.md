# Debugging stenogit services

A guide to diagnosing problems with stenogit's systemd units. All
examples use `--user` (user scope); drop it and add `sudo` for
system-scope units.

## 1. Check if the unit is running

```sh
systemctl --user status stenogit-watch@myinst.service
```

Key signals in the output:

- **Active line**: `active (running)`, `inactive (dead)`,
  `activating (auto-restart)`, `failed`
- **Exit code**: `status=0/SUCCESS`, `status=127/n/a` (command not
  found), `status=1/FAILURE`
- **Last few log lines** appear inline

For timer-backed instances:

```sh
systemctl --user list-timers --all
```

Shows when each timer last fired and when it will fire next.

## 2. Read the journal

```sh
journalctl --user -u stenogit-watch@myinst.service --no-pager
```

Shows everything the service printed to stdout/stderr, plus systemd
lifecycle messages (started, exited, restarted). Useful flags:

- `-n 50`: limit to the last 50 lines
- `-f`: follow in real time

## 3. Check what systemd sees

```sh
systemctl --user show-environment
```

Shows the PATH and other env vars systemd passes to units. Systemd's
PATH is minimal compared to an interactive shell; a command that works
in your terminal may not be found by systemd.

```sh
systemctl --user cat stenogit-watch@myinst.service
```

Shows the full resolved unit file, including any drop-in overrides
applied on top.

## 4. Common exit codes

| Code | Meaning |
|------|---------|
| 0    | Success |
| 1    | Generic script failure (your code returned 1) |
| 126  | Permission denied (file exists but is not executable) |
| 127  | Command not found (a binary in ExecStart or called by the script is not on PATH) |
| 203  | EXEC: systemd itself could not exec the ExecStart binary |
| 217  | USER: the User= specified in the unit does not exist |

## 5. Test the script outside systemd

Run the same command systemd would, with the same env vars:

```sh
source ~/.config/stenogit/myinst.conf
INSTANCE=myinst stenogit-watch
```

For system-scope instances:

```sh
source /etc/stenogit/myinst.conf
INSTANCE=myinst sudo stenogit-watch
```

If this works in your shell but fails under systemd, the problem is
environment (PATH, HOME, missing env vars).

## 6. Trigger a timer-backed service manually

Instead of waiting for the next timer tick:

```sh
systemctl --user start stenogit@myinst.service
```

This fires the oneshot immediately so you can check the journal right
away.

## Quick reference

| What              | Command                                        |
|-------------------|------------------------------------------------|
| Status            | `systemctl --user status <unit>`               |
| Logs              | `journalctl --user -u <unit> -f`               |
| Timer schedule    | `systemctl --user list-timers`                 |
| Env vars          | `systemctl --user show-environment`            |
| Resolved unit     | `systemctl --user cat <unit>`                  |
| Manual trigger    | `systemctl --user start <unit>`                |
| Reload after edit | `systemctl --user daemon-reload`               |
