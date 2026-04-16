#!/usr/bin/env bash
# Common helpers for all bats test files.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
export BIN_DIR="$PROJECT_ROOT/bin"

# Point HOME and the config dirs at the per-test temp dir so nothing
# touches the real filesystem outside BATS_TEST_TMPDIR.
setup_temp_home() {
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    export XDG_CONFIG_HOME="$HOME/.config"
    export STENOGIT_SKIP_ROOT_CHECK=1
}

# Set user-scope base paths (for tests that exercise --user mode).
setup_user_paths() {
    export STENOGIT_USER_CONFIG_DIR="$HOME/.config/stenogit"
    export STENOGIT_USER_SYSTEMD_DIR="$HOME/.config/systemd/user"
}

# Set system-scope base paths (redirected to temp dir for tests).
setup_system_paths() {
    export STENOGIT_SYSTEM_CONFIG_DIR="$BATS_TEST_TMPDIR/etc/stenogit"
    export STENOGIT_SYSTEM_SYSTEMD_DIR="$BATS_TEST_TMPDIR/etc/systemd/system"
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

# Create a mock systemctl binary on PATH that logs all invocations.
setup_mock_systemctl() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/systemctl" <<'MOCK'
#!/bin/bash
echo "$@" >> "$SYSTEMCTL_LOG"
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/systemctl"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}
