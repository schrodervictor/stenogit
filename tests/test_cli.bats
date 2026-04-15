#!/usr/bin/env bats

load test_helper

setup() {
    setup_temp_home
    source "$BIN_DIR/stenogit"
    SYSTEMCTL_LOG="$BATS_TEST_TMPDIR/systemctl.log"
    : > "$SYSTEMCTL_LOG"
    # Mock systemctl by overriding the wrapper so the CLI never touches
    # the real system bus.
    sg_systemctl() { echo "$@" >> "$SYSTEMCTL_LOG"; }
}

@test "add rejects names with a slash" {
    local dir
    dir="$BATS_TEST_TMPDIR/d"
    mkdir -p "$dir"
    run cmd_add "bad/name" "$dir"
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid instance name"* ]]
}

@test "add rejects empty name" {
    local dir
    dir="$BATS_TEST_TMPDIR/d"
    mkdir -p "$dir"
    run cmd_add "" "$dir"
    [ "$status" -ne 0 ]
}

@test "add rejects names with shell metacharacters" {
    local dir
    dir="$BATS_TEST_TMPDIR/d"
    mkdir -p "$dir"
    run cmd_add 'foo;bar' "$dir"
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid instance name"* ]]
}

@test "add errors when target directory does not exist" {
    run cmd_add "myname" "$BATS_TEST_TMPDIR/nope"
    [ "$status" -ne 0 ]
    [[ "$output" == *"does not exist"* ]]
}

@test "add initialises a git repo in the target" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir"
    [ -d "$dir/.git" ]
}

@test "add sets a default git identity when none is given" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir"
    [ -n "$(git -C "$dir" config user.name)" ]
    [ -n "$(git -C "$dir" config user.email)" ]
}

@test "add sets git identity from --git-name and --git-email" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --git-name "Foo Bar" --git-email "foo@example.com"
    [ "$(git -C "$dir" config user.name)" = "Foo Bar" ]
    [ "$(git -C "$dir" config user.email)" = "foo@example.com" ]
}

@test "add writes the conf file with expected keys" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --message "hello {date}" --debounce 7
    local conf="$STENOGIT_CONFIG_DIR/myinst.conf"
    [ -f "$conf" ]
    grep -qx "DIR=$dir" "$conf"
    grep -qx "MESSAGE_TEMPLATE=hello {date}" "$conf"
    grep -qx "DEBOUNCE=7" "$conf"
}

@test "add --schedule writes a timer drop-in with the interval" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --schedule "10min"
    local dropin="$STENOGIT_SYSTEMD_DIR/stenogit@myinst.timer.d/schedule.conf"
    [ -f "$dropin" ]
    grep -q "OnUnitActiveSec=10min" "$dropin"
    # Also clears the inherited value first.
    grep -q "^OnUnitActiveSec=$" "$dropin"
}

@test "add --watch enables the watch service" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --watch
    grep -q "enable --now stenogit-watch@myinst.service" "$SYSTEMCTL_LOG"
}

@test "add (default) enables the timer" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir"
    grep -q "enable --now stenogit@myinst.timer" "$SYSTEMCTL_LOG"
}

@test "add --schedule and --watch are mutually exclusive" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    run cmd_add "myinst" "$dir" --schedule 5min --watch
    [ "$status" -ne 0 ]
    [[ "$output" == *"mutually exclusive"* ]]
}

@test "add issues a daemon-reload" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir"
    grep -q "daemon-reload" "$SYSTEMCTL_LOG"
}

@test "remove deletes the conf file" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir"
    [ -f "$STENOGIT_CONFIG_DIR/myinst.conf" ]
    cmd_remove "myinst"
    [ ! -f "$STENOGIT_CONFIG_DIR/myinst.conf" ]
}

@test "remove disables the systemd units" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir"
    : > "$SYSTEMCTL_LOG"
    cmd_remove "myinst"
    grep -q "disable --now stenogit@myinst.timer" "$SYSTEMCTL_LOG"
    grep -q "disable --now stenogit-watch@myinst.service" "$SYSTEMCTL_LOG"
}

@test "remove deletes the timer drop-in" {
    local dir="$BATS_TEST_TMPDIR/target"
    mkdir -p "$dir"
    cmd_add "myinst" "$dir" --schedule 5min
    local dropdir="$STENOGIT_SYSTEMD_DIR/stenogit@myinst.timer.d"
    [ -d "$dropdir" ]
    cmd_remove "myinst"
    [ ! -d "$dropdir" ]
}

@test "list shows configured instances" {
    local d1="$BATS_TEST_TMPDIR/d1"
    local d2="$BATS_TEST_TMPDIR/d2"
    mkdir -p "$d1" "$d2"
    cmd_add "first" "$d1"
    cmd_add "second" "$d2"
    run cmd_list
    [ "$status" -eq 0 ]
    [[ "$output" == *"first"* ]]
    [[ "$output" == *"second"* ]]
}

@test "list shows nothing when none configured" {
    run cmd_list
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
