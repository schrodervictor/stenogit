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
