# inotify resource considerations

Notes on inotify's resource profile and watch limits, relevant to
stenogit's `--watch` mode.

## How inotify works

inotify is a Linux kernel subsystem for monitoring filesystem events.
It is event-driven, not polling-based:

- **No CPU cost while idle.** The kernel notifies the process when
  something happens. Between events, `inotifywait` sleeps on a file
  descriptor.
- **No disk I/O overhead.** Watches are hooks in the VFS layer, not
  periodic scans.
- **Memory cost is per-watch.** Each watched directory (not file)
  consumes one inotify watch. The kernel allocates a small struct per
  watch, roughly 1 KB each.

For stenogit's typical use cases, inotify is essentially free.

## Watch limits

The kernel enforces a per-user limit on the number of simultaneous
inotify watches. With `--recursive` (which stenogit uses),
`inotifywait` creates one watch per subdirectory in the tree.

The default limit on most distributions is 8,192 or 65,536. Check the
current value with:

```sh
cat /proc/sys/fs/inotify/max_user_watches
```

### Typical directory sizes

- `/etc/nginx`: a dozen subdirectories
- `~/dotfiles`: a few hundred at most
- A large project tree: a few thousand

For these sizes, even the default limit is plenty. The concern arises
when many watch instances run simultaneously on large trees, or when
other tools (VS Code, JetBrains IDEs) are also consuming watches on
the same user.

### Raising the limit

Temporarily (until reboot):

```sh
sudo sysctl fs.inotify.max_user_watches=524288
```

Permanently (create or edit `/etc/sysctl.d/90-inotify.conf`):

```
fs.inotify.max_user_watches=524288
```

### Memory cost at different limits

| Watches | Approximate memory |
|---------|--------------------|
| 8,192 (common default) | ~8 MB |
| 65,536 | ~64 MB |
| 524,288 (common recommendation) | ~512 MB |
| 1,048,576 | ~1 GB |

The kernel's compiled-in maximum is 2^30 (about 1 billion). In
practice, memory is the real constraint.

### Symptoms of hitting the limit

`inotifywait` fails with:

```
Failed to watch /some/path; upper limit on inotify watches reached!
```

or the less obvious:

```
No space left on device
```

Despite the message, this refers to watch slots, not disk space.

## Platform availability

inotify is Linux-only. macOS uses FSEvents/kqueue, and Windows uses
ReadDirectoryChangesW. Cross-platform alternatives like `fswatch` or
`watchman` abstract over these, but stenogit currently targets Linux
exclusively due to its systemd dependency.
