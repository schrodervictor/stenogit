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
    # Two bursts, each 1.5s long, separated by a gap longer than debounce.
    # Max-wait=1. Each burst should trigger exactly one commit from the
    # ceiling, and the second burst should get its own fresh max-wait
    # window (not fire immediately because the old deadline carried over).
    #
    # Record timestamps of each commit to verify the second one is not
    # premature.
    sgw_run_commit() {
        date +%s >> "$FIRES_FILE"
    }
    (
        # Burst 1: events every 0.2s for 1.5s
        for i in $(seq 1 7); do echo "ev$i"; sleep 0.2; done
        # Gap: longer than debounce (0.5s), so any pending debounce fires
        sleep 1
        # Burst 2: events every 0.2s for 1.5s
        for i in $(seq 1 7); do echo "ev$i"; sleep 0.2; done
    ) | sgw_debounce_loop 0.5 1
    local fires
    fires=$(wc -l < "$FIRES_FILE" | tr -d '[:space:]')
    # At least 2 commits (one per burst from ceiling or debounce).
    [ "$fires" -ge 2 ]
    # The second commit's timestamp should be at least 0.8s after the
    # first, proving it got its own max-wait window rather than firing
    # immediately from a stale deadline.
    if [ "$fires" -ge 2 ]; then
        local t1 t2
        t1=$(sed -n '1p' "$FIRES_FILE")
        t2=$(sed -n '2p' "$FIRES_FILE")
        [ "$(( t2 - t1 ))" -ge 1 ]
    fi
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
