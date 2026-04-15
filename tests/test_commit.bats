#!/usr/bin/env bats

load test_helper

setup() {
    setup_temp_home
    unset DIR INSTANCE MESSAGE_TEMPLATE
    source "$BIN_DIR/stenogit-commit"
}

@test "errors when DIR is unset" {
    run sg_main
    [ "$status" -ne 0 ]
    [[ "$output" == *"DIR is required"* ]]
}

@test "errors when target dir does not exist" {
    DIR="$BATS_TEST_TMPDIR/nope" run sg_main
    [ "$status" -ne 0 ]
    [[ "$output" == *"directory does not exist"* ]]
}

@test "errors when target is not a git repository" {
    local dir="$BATS_TEST_TMPDIR/notarepo"
    mkdir -p "$dir"
    DIR="$dir" run sg_main
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a git repository"* ]]
}

@test "no-op when nothing has changed (empty repo)" {
    local dir
    dir=$(make_git_repo)
    DIR="$dir" run sg_main
    [ "$status" -eq 0 ]
    # No commits exist on the empty repo.
    run git -C "$dir" rev-parse HEAD
    [ "$status" -ne 0 ]
}

@test "no-op when nothing has changed (clean working tree)" {
    local dir
    dir=$(make_git_repo)
    echo hi > "$dir/file"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "seed"
    local before
    before=$(git -C "$dir" rev-parse HEAD)
    DIR="$dir" run sg_main
    [ "$status" -eq 0 ]
    [ "$(git -C "$dir" rev-parse HEAD)" = "$before" ]
}

@test "commits added files" {
    local dir
    dir=$(make_git_repo)
    echo hello > "$dir/file.txt"
    DIR="$dir" run sg_main
    [ "$status" -eq 0 ]
    run git -C "$dir" log --oneline
    [ "${#lines[@]}" -eq 1 ]
}

@test "commits modified files" {
    local dir
    dir=$(make_git_repo)
    echo v1 > "$dir/file.txt"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "initial"
    echo v2 > "$dir/file.txt"
    DIR="$dir" run sg_main
    [ "$status" -eq 0 ]
    run git -C "$dir" log --oneline
    [ "${#lines[@]}" -eq 2 ]
}

@test "commits deleted files" {
    local dir
    dir=$(make_git_repo)
    echo v1 > "$dir/file.txt"
    git -C "$dir" add -A
    git -C "$dir" commit -q -m "initial"
    rm "$dir/file.txt"
    DIR="$dir" run sg_main
    [ "$status" -eq 0 ]
    run git -C "$dir" log --oneline
    [ "${#lines[@]}" -eq 2 ]
}

@test "default message template is applied if MESSAGE_TEMPLATE unset" {
    local dir
    dir=$(make_git_repo)
    echo x > "$dir/f"
    DIR="$dir" sg_main
    local msg
    msg=$(git -C "$dir" log -1 --pretty=%s)
    [[ "$msg" == "auto: "* ]]
}

@test "sg_expand_template expands {date} placeholder" {
    date() { echo "FAKEDATE"; }
    run sg_expand_template "msg {date}" "inst" "1"
    [ "$output" = "msg FAKEDATE" ]
}

@test "sg_expand_template expands {count} placeholder" {
    run sg_expand_template "n={count}" "inst" "42"
    [ "$output" = "n=42" ]
}

@test "sg_expand_template expands {name} placeholder from instance arg" {
    run sg_expand_template "from {name}" "myinst" "1"
    [ "$output" = "from myinst" ]
}

@test "sg_expand_template expands {host} placeholder" {
    hostname() { echo "FAKEHOST"; }
    run sg_expand_template "on {host}" "inst" "1"
    [ "$output" = "on FAKEHOST" ]
}

@test "sg_expand_template expands multiple placeholders in one template" {
    date() { echo "D"; }
    hostname() { echo "H"; }
    run sg_expand_template "{name}@{host} {count} {date}" "I" "3"
    [ "$output" = "I@H 3 D" ]
}

@test "sg_expand_template repeats expansion when placeholder appears twice" {
    run sg_expand_template "{count}-{count}" "I" "7"
    [ "$output" = "7-7" ]
}

@test "{count} placeholder reflects number of changed files via main" {
    local dir
    dir=$(make_git_repo)
    echo a > "$dir/a"
    echo b > "$dir/b"
    echo c > "$dir/c"
    DIR="$dir" MESSAGE_TEMPLATE="commit {count}" sg_main
    [ "$(git -C "$dir" log -1 --pretty=%s)" = "commit 3" ]
}

@test "{name} placeholder reflects INSTANCE via main" {
    local dir
    dir=$(make_git_repo)
    echo x > "$dir/f"
    DIR="$dir" INSTANCE="webconf" MESSAGE_TEMPLATE="from {name}" sg_main
    [ "$(git -C "$dir" log -1 --pretty=%s)" = "from webconf" ]
}

@test "initial commit on a fresh repo with files" {
    local dir
    dir=$(make_git_repo)
    echo x > "$dir/a"
    echo y > "$dir/b"
    DIR="$dir" run sg_main
    [ "$status" -eq 0 ]
    run git -C "$dir" log --oneline
    [ "${#lines[@]}" -eq 1 ]
    run git -C "$dir" ls-files
    [ "${#lines[@]}" -eq 2 ]
}
