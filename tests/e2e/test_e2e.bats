#!/usr/bin/env bats
#
# End-to-end tests running against real systemd inside a podman container.
# These are NOT included in the regular `make test` run. Use `make test-e2e`.
#
# Prerequisites (handled by the Makefile target):
#   - Container started with systemd as PID 1
#   - stenogit installed to /usr via make install PREFIX=/usr
#   - systemctl daemon-reload already run

setup() {
    TEST_DIR="/tmp/stenogit-e2e-$$-$BATS_TEST_NUMBER"
    mkdir -p "$TEST_DIR"
    git config --global user.name "E2E Test"
    git config --global user.email "e2e@test"
}

teardown() {
    # Best-effort cleanup; some tests remove their own instance.
    stenogit remove "e2e$$n" 2>/dev/null || true
    rm -rf "$TEST_DIR"
}

wait_for_unit() {
    local unit="$1"
    local timeout="${2:-5}"
    local i=0
    while [[ $i -lt $timeout ]]; do
        if systemctl is-active --quiet "$unit" 2>/dev/null; then
            return 0
        fi
        sleep 1
        (( i++ ))
    done
    return 1
}

### timer mode: full lifecycle

@test "add enables a timer that can fire a commit" {
    local name="e2e$$t"
    mkdir -p "$TEST_DIR/tracked"
    echo "seed" > "$TEST_DIR/tracked/file.txt"

    stenogit add "$name" "$TEST_DIR/tracked" --git-name "E2E" --git-email "e2e@test"

    # Timer should be active.
    systemctl is-active "stenogit@$name.timer"

    # Conf file should exist.
    [ -f "/etc/stenogit/$name.conf" ]

    # Trigger the oneshot service manually instead of waiting for the timer.
    systemctl start "stenogit@$name.service"

    # Verify the commit landed.
    run git -C "$TEST_DIR/tracked" log --oneline
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ge 1 ]

    # Clean up.
    stenogit remove "$name"
    ! systemctl is-active --quiet "stenogit@$name.timer" 2>/dev/null
    [ ! -f "/etc/stenogit/$name.conf" ]
}

### timer mode: schedule override

@test "add --schedule writes a drop-in and timer respects it" {
    local name="e2e$$s"
    mkdir -p "$TEST_DIR/tracked"

    stenogit add "$name" "$TEST_DIR/tracked" --schedule 30s

    # Drop-in should exist with the custom interval.
    local dropin="/etc/systemd/system/stenogit@$name.timer.d/schedule.conf"
    [ -f "$dropin" ]
    grep -q "OnUnitActiveSec=30s" "$dropin"

    # Timer should be active.
    systemctl is-active "stenogit@$name.timer"

    stenogit remove "$name"
    [ ! -d "/etc/systemd/system/stenogit@$name.timer.d" ]
}

### watch mode: inotify triggers commit

@test "add --watch enables the watcher and commits on file change" {
    local name="e2e$$w"
    mkdir -p "$TEST_DIR/tracked"

    stenogit add "$name" "$TEST_DIR/tracked" --watch \
        --debounce 1 --max-wait 5 \
        --git-name "E2E" --git-email "e2e@test"

    # Watch service should be active.
    wait_for_unit "stenogit-watch@$name.service"
    # Give inotifywait time to set up watches before writing.
    sleep 1

    # Write a file; the watcher should pick it up after debounce.
    echo "hello" > "$TEST_DIR/tracked/new-file.txt"
    sleep 4

    run git -C "$TEST_DIR/tracked" log --oneline
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -ge 1 ]

    stenogit remove "$name"
    ! systemctl is-active --quiet "stenogit-watch@$name.service" 2>/dev/null
}

### list: shows active instances

@test "list shows instances with correct scope" {
    local name="e2e$$l"
    mkdir -p "$TEST_DIR/tracked"

    stenogit add "$name" "$TEST_DIR/tracked"

    run stenogit list
    [ "$status" -eq 0 ]
    [[ "$output" == *"$name"* ]]
    [[ "$output" == *"system"* ]]

    stenogit remove "$name"
}

### remove: idempotent and complete

@test "remove cleans up config, drop-in, and units" {
    local name="e2e$$r"
    mkdir -p "$TEST_DIR/tracked"

    stenogit add "$name" "$TEST_DIR/tracked" --schedule 45s

    # Everything should exist.
    [ -f "/etc/stenogit/$name.conf" ]
    [ -d "/etc/systemd/system/stenogit@$name.timer.d" ]
    systemctl is-active "stenogit@$name.timer"

    stenogit remove "$name"

    # Everything should be gone.
    [ ! -f "/etc/stenogit/$name.conf" ]
    [ ! -d "/etc/systemd/system/stenogit@$name.timer.d" ]
    ! systemctl is-active --quiet "stenogit@$name.timer" 2>/dev/null
}
