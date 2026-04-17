#!/usr/bin/env bats

load test_helper

setup() {
    setup_temp_home
    unset DIR DEBOUNCE
    source "$BIN_DIR/stenogit-watch"
    FIRES_FILE="$BATS_TEST_TMPDIR/fires"
    : > "$FIRES_FILE"
    # Override the commit invocation so we can observe and count fires
    # without spawning anything real.
    sgw_run_commit() { echo "FIRE" >> "$FIRES_FILE"; }
}

count_fires() {
    wc -l < "$FIRES_FILE" | tr -d '[:space:]'
}

@test "single event triggers exactly one commit" {
    echo "ev1" | sgw_debounce_loop 0.5
    [ "$(count_fires)" -eq 1 ]
}

@test "burst of events within window triggers exactly one commit" {
    printf 'a\nb\nc\nd\n' | sgw_debounce_loop 0.5
    [ "$(count_fires)" -eq 1 ]
}

@test "events separated by more than the window trigger two commits" {
    ( echo "a"; sleep 1; echo "b" ) | sgw_debounce_loop 0.3
    [ "$(count_fires)" -eq 2 ]
}

@test "no events means no commit" {
    : | sgw_debounce_loop 0.3
    [ "$(count_fires)" -eq 0 ]
}

@test "sgw_main errors when DIR is unset" {
    run sgw_main
    [ "$status" -ne 0 ]
    [[ "$output" == *"DIR is required"* ]]
}

@test "sgw_main errors when DIR does not exist" {
    DIR="$BATS_TEST_TMPDIR/nope" run sgw_main
    [ "$status" -ne 0 ]
    [[ "$output" == *"directory does not exist"* ]]
}

@test "commit failure does not stop the debounce loop" {
    sgw_run_commit() { echo "FIRE" >> "$FIRES_FILE"; return 1; }
    printf 'a\nb\n' | sgw_debounce_loop 0.5
    [ "$(count_fires)" -eq 1 ]
}

### max-wait: ceiling on debounce delay

@test "max-wait forces commit during sustained churn" {
    # Send events every 0.2s for 2s. With debounce=0.5 and no max-wait,
    # this would produce one commit at the end. With max-wait=1, the
    # ceiling should force at least one mid-stream commit.
    (
        for i in $(seq 1 10); do
            echo "ev$i"
            sleep 0.2
        done
    ) | sgw_debounce_loop 0.5 1
    [ "$(count_fires)" -ge 2 ]
}

@test "max-wait resets after commit (does not bleed into next burst)" {
    # Two bursts, each ~2s long, separated by a gap longer than debounce.
    # Max-wait=2. If the deadline leaked from burst 1 into burst 2, the
    # second burst would fire an immediate premature commit (stale
    # deadline already passed), producing extra fires. We verify the
    # total commit count stays bounded, proving each burst got its own
    # fresh max-wait window.
    (
        # Burst 1: events every 0.2s for ~2s
        for i in $(seq 1 10); do echo "ev$i"; sleep 0.2; done
        # Gap: longer than debounce so any pending debounce fires
        sleep 1.5
        # Burst 2: events every 0.2s for ~2s
        for i in $(seq 1 10); do echo "ev$i"; sleep 0.2; done
    ) | sgw_debounce_loop 0.5 2
    local fires
    fires=$(count_fires)
    # Each burst produces at most 1 ceiling commit + 1 debounce commit.
    # With leaked deadline, burst 2 would fire immediately, inflating
    # the count. Two bursts should yield 2-4 fires total.
    [ "$fires" -ge 2 ]
    [ "$fires" -le 4 ]
}

@test "max-wait=0 disables the ceiling" {
    # Sustained events for 1.5s with debounce=0.5 and max-wait=0.
    # Without a ceiling, only one commit should fire (after the stream
    # ends and debounce expires).
    (
        for i in $(seq 1 7); do echo "ev$i"; sleep 0.2; done
    ) | sgw_debounce_loop 0.5 0
    [ "$(count_fires)" -eq 1 ]
}

### initial commit: pre-existing changes

@test "sgw_main runs an initial commit before entering the watch loop" {
    local dir="$BATS_TEST_TMPDIR/watched"
    mkdir -p "$dir"
    # Mock inotifywait to exit immediately with no output.
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/bash\n' > "$BATS_TEST_TMPDIR/bin/inotifywait"
    chmod +x "$BATS_TEST_TMPDIR/bin/inotifywait"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    DIR="$dir" sgw_main
    [ "$(count_fires)" -eq 1 ]
}

@test "sgw_main initial commit plus events produces correct fire count" {
    local dir="$BATS_TEST_TMPDIR/watched"
    mkdir -p "$dir"
    # Mock inotifywait to emit one event then exit.
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    printf '#!/bin/bash\necho "event"\n' > "$BATS_TEST_TMPDIR/bin/inotifywait"
    chmod +x "$BATS_TEST_TMPDIR/bin/inotifywait"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    DIR="$dir" sgw_main
    [ "$(count_fires)" -eq 2 ]
}

### inotifywait: integration with real filesystem
#
# These tests run real inotifywait with --timeout to avoid hangs.
# inotifywait --timeout exits after N seconds regardless of events,
# which closes the pipe and lets the debounce loop drain and exit.

@test "inotifywait detects changes in deeply nested directories" {
    local dir="$BATS_TEST_TMPDIR/watched"
    mkdir -p "$dir/a/b/c"

    # Start inotifywait with a timeout; write a nested file after a short delay.
    (sleep 0.5; echo "data" > "$dir/a/b/c/deep.txt") &

    inotifywait --monitor --recursive --quiet \
        --exclude '/\.git/' \
        --timeout 3 \
        --event modify,create,delete,move \
        "$dir" \
        | sgw_debounce_loop 1 0

    [ "$(count_fires)" -ge 1 ]
}

@test "inotifywait excludes .git directory" {
    local dir="$BATS_TEST_TMPDIR/watched"
    mkdir -p "$dir/.git/objects"

    # Only write inside .git after a short delay.
    (sleep 0.5; echo "blob" > "$dir/.git/objects/abc123"; echo "ref" > "$dir/.git/HEAD") &

    inotifywait --monitor --recursive --quiet \
        --exclude '/\.git/' \
        --timeout 3 \
        --event modify,create,delete,move \
        "$dir" \
        | sgw_debounce_loop 1 0

    [ "$(count_fires)" -eq 0 ]
}

@test "inotifywait fires on real changes but ignores .git writes" {
    local dir="$BATS_TEST_TMPDIR/watched"
    mkdir -p "$dir/.git/objects"

    # Write to .git first (ignored), then a real file (triggers commit).
    (
        sleep 0.5
        echo "blob" > "$dir/.git/objects/abc123"
        sleep 0.3
        echo "real" > "$dir/config.conf"
    ) &

    inotifywait --monitor --recursive --quiet \
        --exclude '/\.git/' \
        --timeout 4 \
        --event modify,create,delete,move \
        "$dir" \
        | sgw_debounce_loop 1 0

    [ "$(count_fires)" -eq 1 ]
}

### watch: env var and error handling

@test "STENOGIT_COMMIT env var selects the commit command" {
    # Restore real sgw_run_commit to test the env var path.
    source "$BIN_DIR/stenogit-watch"
    local tracker="$BATS_TEST_TMPDIR/tracker"
    printf '#!/bin/bash\necho FIRE >> "%s"\n' "$FIRES_FILE" > "$tracker"
    chmod +x "$tracker"
    echo "ev1" | STENOGIT_COMMIT="$tracker" sgw_debounce_loop 0.5 0
    [ "$(count_fires)" -eq 1 ]
}
