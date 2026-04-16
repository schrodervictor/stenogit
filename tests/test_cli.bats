#!/usr/bin/env bats

load test_helper

setup() {
    setup_temp_home
    setup_user_paths
    source "$BIN_DIR/stenogit"
    export SYSTEMCTL_LOG="$BATS_TEST_TMPDIR/systemctl.log"
    : > "$SYSTEMCTL_LOG"
    sg_systemctl() { echo "$@" >> "$SYSTEMCTL_LOG"; }
}

# ── name validation (scope-independent) ─────────────────────────────

@test "add rejects names with a slash" {
    local dir="$BATS_TEST_TMPDIR/d"
    mkdir -p "$dir"
    run cmd_add "bad/name" "$dir" --user
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid instance name"* ]]
}

@test "add rejects empty name" {
    local dir="$BATS_TEST_TMPDIR/d"
    mkdir -p "$dir"
    run cmd_add "" "$dir" --user
    [ "$status" -ne 0 ]
    [[ "$output" == *"instance name is required"* ]]
}

@test "add rejects names with shell metacharacters" {
    local dir="$BATS_TEST_TMPDIR/d"
    mkdir -p "$dir"
    run cmd_add 'foo;bar' "$dir" --user
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid instance name"* ]]
}

@test "add errors when target directory does not exist" {
    run cmd_add "myname" "$BATS_TEST_TMPDIR/nope" --user
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
}

# ── user mode (--user) ──────────────────────────────────────────────

@test "add --user initialises a git repo in the target" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user
    [ -d "$dir/.git" ]
}

@test "add --user sets a default git identity when none is given" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user
    [ -n "$(git -C "$dir" config user.name)" ]
    [ -n "$(git -C "$dir" config user.email)" ]
}

@test "add --user sets git identity from --git-name and --git-email" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user --git-name "Foo Bar" --git-email "foo@example.com"
    [ "$(git -C "$dir" config user.name)" = "Foo Bar" ]
    [ "$(git -C "$dir" config user.email)" = "foo@example.com" ]
}

@test "add --user writes the conf file with expected keys" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user --message "hello {date}" --debounce 7
    local conf="$STENOGIT_USER_CONFIG_DIR/myinst.conf"
    [ -f "$conf" ]
    grep -qx "DIR=$dir" "$conf"
    grep -qx "MESSAGE_TEMPLATE=hello {date}" "$conf"
    grep -qx "DEBOUNCE=7" "$conf"
}

@test "add --user --schedule writes a timer drop-in with the interval" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user --schedule "10min"
    local dropin="$STENOGIT_USER_SYSTEMD_DIR/stenogit@myinst.timer.d/schedule.conf"
    [ -f "$dropin" ]
    grep -q "OnUnitActiveSec=10min" "$dropin"
    grep -q "^OnUnitActiveSec=$" "$dropin"
}

@test "add --user --watch enables the watch service" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user --watch
    grep -q "enable --now stenogit-watch@myinst.service" "$SYSTEMCTL_LOG"
}

@test "add --user (default trigger) enables the timer" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user
    grep -q "enable --now stenogit@myinst.timer" "$SYSTEMCTL_LOG"
}

@test "add --schedule and --watch are mutually exclusive" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    run cmd_add "myinst" "$dir" --user --schedule 5min --watch
    [ "$status" -ne 0 ]
    [[ "$output" == *"mutually exclusive"* ]]
}

@test "add --user issues a daemon-reload" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user
    grep -q "daemon-reload" "$SYSTEMCTL_LOG"
}

@test "add --user systemctl receives --user flag" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    # Restore real sg_systemctl and mock systemctl binary on PATH.
    source "$BIN_DIR/stenogit"
    setup_mock_systemctl
    cmd_add "myinst" "$dir" --user
    grep -q "^--user " "$SYSTEMCTL_LOG"
}

# ── system mode (default) ──────────────────────────────────────────

@test "add (system default) writes conf to system config dir" {
    setup_system_paths
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir"
    [ -f "$STENOGIT_SYSTEM_CONFIG_DIR/myinst.conf" ]
    grep -qx "DIR=$dir" "$STENOGIT_SYSTEM_CONFIG_DIR/myinst.conf"
}

@test "add (system default) enables the timer" {
    setup_system_paths
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir"
    grep -q "enable --now stenogit@myinst.timer" "$SYSTEMCTL_LOG"
}

@test "add (system default) systemctl omits --user flag" {
    setup_system_paths
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    source "$BIN_DIR/stenogit"
    setup_mock_systemctl
    cmd_add "myinst" "$dir"
    ! grep -q "^--user " "$SYSTEMCTL_LOG"
}

@test "add (system default) requires root without STENOGIT_SKIP_ROOT_CHECK" {
    setup_system_paths
    unset STENOGIT_SKIP_ROOT_CHECK
    # Mock id to return non-root UID (container runs as root).
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/bash\necho 1000\n' > "$BATS_TEST_TMPDIR/bin/id"
    chmod +x "$BATS_TEST_TMPDIR/bin/id"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    run cmd_add "myinst" "$dir"
    [ "$status" -ne 0 ]
    [[ "$output" == *"system mode requires root"* ]]
    [[ "$output" == *"--user"* ]]
}

# ── remove ──────────────────────────────────────────────────────────

@test "remove --user deletes the conf file" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user
    [ -f "$STENOGIT_USER_CONFIG_DIR/myinst.conf" ]
    cmd_remove "myinst" --user
    [ ! -f "$STENOGIT_USER_CONFIG_DIR/myinst.conf" ]
}

@test "remove --user disables the systemd units" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user
    : > "$SYSTEMCTL_LOG"
    cmd_remove "myinst" --user
    grep -q "disable --now stenogit@myinst.timer" "$SYSTEMCTL_LOG"
    grep -q "disable --now stenogit-watch@myinst.service" "$SYSTEMCTL_LOG"
}

@test "remove --user deletes the timer drop-in" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user --schedule 5min
    local dropdir="$STENOGIT_USER_SYSTEMD_DIR/stenogit@myinst.timer.d"
    [ -d "$dropdir" ]
    cmd_remove "myinst" --user
    [ ! -d "$dropdir" ]
}

@test "remove auto-detects user scope" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user
    [ -f "$STENOGIT_USER_CONFIG_DIR/myinst.conf" ]
    cmd_remove "myinst"
    [ ! -f "$STENOGIT_USER_CONFIG_DIR/myinst.conf" ]
}

@test "remove auto-detects system scope" {
    setup_system_paths
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir"
    [ -f "$STENOGIT_SYSTEM_CONFIG_DIR/myinst.conf" ]
    cmd_remove "myinst"
    [ ! -f "$STENOGIT_SYSTEM_CONFIG_DIR/myinst.conf" ]
}

@test "remove errors when instance not found" {
    setup_system_paths
    run cmd_remove "nope"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no instance found"* ]]
}

# ── list ────────────────────────────────────────────────────────────

@test "list shows user instances with scope" {
    setup_system_paths
    local dir="$BATS_TEST_TMPDIR/d1"
    mkdir -p "$dir"
    cmd_add "first" "$dir" --user
    run cmd_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"first"* ]]
    [[ "$output" == *"user"* ]]
}

@test "list shows system instances with scope" {
    setup_system_paths
    local dir="$BATS_TEST_TMPDIR/d1"
    mkdir -p "$dir"
    cmd_add "sysone" "$dir"
    run cmd_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"sysone"* ]]
    [[ "$output" == *"system"* ]]
}

@test "list shows both scopes" {
    setup_system_paths
    local d1="$BATS_TEST_TMPDIR/d1"
    local d2="$BATS_TEST_TMPDIR/d2"
    mkdir -p "$d1" "$d2"
    cmd_add "sysone" "$d1"
    cmd_add "userone" "$d2" --user
    run cmd_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"sysone"*"system"* ]]
    [[ "$output" == *"userone"*"user"* ]]
}

@test "list shows nothing when none configured" {
    setup_system_paths
    run cmd_list
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ── argument parsing edge cases ─────────────────────────────────────

@test "add rejects unknown option" {
    local dir="$BATS_TEST_TMPDIR/d"
    mkdir -p "$dir"
    run cmd_add "myinst" "$dir" --user --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option: --bogus"* ]]
}

@test "add rejects names with whitespace" {
    local dir="$BATS_TEST_TMPDIR/d"
    mkdir -p "$dir"
    run cmd_add "has space" "$dir" --user
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid instance name"* ]]
}

@test "add with too few arguments prints usage" {
    run cmd_add "onlyname"
    [ "$status" -ne 0 ]
}

@test "remove rejects unknown option" {
    run cmd_remove "myinst" --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option: --bogus"* ]]
}

@test "unknown subcommand fails" {
    run sg_main "badcmd"
    [ "$status" -ne 0 ]
}

@test "no subcommand prints usage" {
    run sg_main ""
    [ "$status" -eq 0 ]
}

# ── directory with spaces ───────────────────────────────────────────

@test "add --user works with spaces in directory path" {
    local dir="$BATS_TEST_TMPDIR/my target dir"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user
    [ -d "$dir/.git" ]
    local conf="$STENOGIT_USER_CONFIG_DIR/myinst.conf"
    [ -f "$conf" ]
    grep -qx "DIR=$dir" "$conf"
}

# ── default git identity ────────────────────────────────────────────

@test "add --user default git identity is Stenogit" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user
    [ "$(git -C "$dir" config user.name)" = "Stenogit" ]
    [[ "$(git -C "$dir" config user.email)" == stenogit@* ]]
}

# ── remove scope mismatch ──────────────────────────────────────────

@test "remove --user does not affect system instance" {
    setup_system_paths
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir"
    [ -f "$STENOGIT_SYSTEM_CONFIG_DIR/myinst.conf" ]
    # Remove in user scope is a no-op — system conf untouched.
    cmd_remove "myinst" --user
    [ -f "$STENOGIT_SYSTEM_CONFIG_DIR/myinst.conf" ]
}

@test "remove idempotent — second remove fails" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --user
    cmd_remove "myinst" --user
    setup_system_paths
    run cmd_remove "myinst"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no instance found"* ]]
}
