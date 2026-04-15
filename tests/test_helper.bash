#!/usr/bin/env bash
# Common helpers for all bats test files.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$PROJECT_ROOT/bin"

# Point HOME and the config dirs at the per-test temp dir so nothing
# touches the real filesystem outside BATS_TEST_TMPDIR.
setup_temp_home() {
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export XDG_CONFIG_HOME="$HOME/.config"
    export CONFIG_TRACKER_CONFIG_DIR="$HOME/.config/config-tracker"
    export CONFIG_TRACKER_SYSTEMD_DIR="$HOME/.config/systemd/user"
}

# Create a fresh git repo under the test tmpdir with a usable identity,
# print its absolute path on stdout.
make_git_repo() {
    local dir
    dir="$(mktemp -d "$BATS_TEST_TMPDIR/repo.XXXXXX")"
    git -C "$dir" init -q
    git -C "$dir" config user.name "Test User"
    git -C "$dir" config user.email "test@example.com"
    printf '%s' "$dir"
}
