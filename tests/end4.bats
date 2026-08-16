#!/usr/bin/env bats

setup() {
    test_root="$(mktemp -d "${TMPDIR:-/tmp}/end4-tests.XXXXXX")"
    repo="$test_root/repo"
    home="$test_root/home"
    upstream_bare="$test_root/upstream.git"
    updater="$test_root/updater"
    mkdir -p "$repo" "$home/config" "$home/data"

    cp "$BATS_TEST_DIRNAME/../end4" "$repo/end4"
    chmod +x "$repo/end4"
    mkdir -p \
        "$repo/dots/.config/hypr/hyprland" \
        "$repo/dots/.config/hypr/custom" \
        "$repo/dots/.config/quickshell" \
        "$repo/dots/.config/fish" \
        "$repo/dots/.config/fontconfig" \
        "$repo/dots/.config/kitty" \
        "$repo/dots/.local/share/konsole" \
        "$repo/local/.config" \
        "$repo/local/.local" \
        "$repo/devices/DarkArch/.config"
    printf 'return {}\n' > "$repo/dots/.config/hypr/hyprland.lua"
    printf 'base lock\n' > "$repo/dots/.config/hypr/hyprlock.conf"
    printf 'base idle\n' > "$repo/dots/.config/hypr/hypridle.conf"
    printf 'return {}\n' > "$repo/dots/.config/hypr/custom/general.lua"
    printf 'device only\n' > "$repo/devices/DarkArch/.config/device.conf"
    printf 'ignored.conf\n' > "$repo/.gitignore"

    git -C "$repo" init -q -b main
    git -C "$repo" config user.name 'end4 tests'
    git -C "$repo" config user.email 'end4-tests@example.invalid'
    git -C "$repo" add .
    git -C "$repo" commit -qm 'fixture base'

    git init -q --bare "$upstream_bare"
    git -C "$repo" remote add upstream "$upstream_bare"
    git -C "$repo" push -q upstream main
    git -C "$repo" fetch -q upstream main

    git clone -q "$upstream_bare" "$updater"
    git -C "$updater" config user.name 'end4 upstream tests'
    git -C "$updater" config user.email 'end4-upstream-tests@example.invalid'
}

teardown() {
    rm -rf -- "$test_root"
}

run_end4() {
    env \
        END4_REPO_ROOT="$repo" \
        HOME="$home" \
        XDG_CONFIG_HOME="$home/config" \
        XDG_DATA_HOME="$home/data" \
        END4_FROM_LAZYGIT=1 \
        "$repo/end4" "$@"
}

make_upstream_commit() {
    local file="$1"
    local content="$2"
    local message="$3"
    printf '%s\n' "$content" > "$updater/$file"
    git -C "$updater" add "$file"
    git -C "$updater" commit -qm "$message"
    git -C "$updater" push -q origin main
}

@test "merge reports no work when upstream has no incoming commits" {
    run run_end4 merge --yes

    [ "$status" -eq 0 ]
    [[ "$output" == *"Already synchronized"* ]]
    run git -C "$repo" rev-parse -q --verify MERGE_HEAD
    [ "$status" -ne 0 ]
}

@test "merge refuses a dirty worktree before fetching or changing state" {
    printf 'local edit\n' >> "$repo/dots/.config/hypr/custom/general.lua"

    run run_end4 merge --yes

    [ "$status" -ne 0 ]
    [[ "$output" == *"working tree is not clean"* ]]
    [ ! -e "$repo/.git/MERGE_HEAD" ]
}

@test "nonconflicting merge is prepared but never committed" {
    make_upstream_commit upstream-only.conf 'upstream content' 'upstream nonconflicting change'

    run run_end4 merge --yes

    [ "$status" -eq 0 ]
    [ -e "$repo/.git/MERGE_HEAD" ]
    run git -C "$repo" diff --cached --name-only
    [[ "$output" == *"upstream-only.conf"* ]]
    run git -C "$repo" log -1 --format=%s
    [ "$output" = 'fixture base' ]
}

@test "conflicting merge leaves conflict paths for LazyGit resolution" {
    printf 'fork value\n' > "$repo/conflict.conf"
    git -C "$repo" add conflict.conf
    git -C "$repo" commit -qm 'custom conflict change'
    printf 'upstream value\n' > "$updater/conflict.conf"
    git -C "$updater" add conflict.conf
    git -C "$updater" commit -qm 'upstream conflict change'
    git -C "$updater" push -q origin main

    run run_end4 merge --yes

    [ "$status" -ne 0 ]
    [ -e "$repo/.git/MERGE_HEAD" ]
    run git -C "$repo" diff --name-only --diff-filter=U
    [[ "$output" == *"conflict.conf"* ]]
    run git -C "$repo" log -1 --format=%s
    [ "$output" = 'custom conflict change' ]
}

@test "discard aborts an active merge before cleaning local state" {
    printf 'fork value\n' > "$repo/abort.conf"
    git -C "$repo" add abort.conf
    git -C "$repo" commit -qm 'custom abort test change'
    printf 'upstream value\n' > "$updater/abort.conf"
    git -C "$updater" add abort.conf
    git -C "$updater" commit -qm 'upstream abort test change'
    git -C "$updater" push -q origin main

    run run_end4 merge --yes
    [ "$status" -ne 0 ]
    [ -e "$repo/.git/MERGE_HEAD" ]

    run run_end4 discard --yes
    [ "$status" -eq 0 ]
    [ ! -e "$repo/.git/MERGE_HEAD" ]
    [ "$(<"$repo/abort.conf")" = 'fork value' ]
    run git -C "$repo" status --porcelain
    [ -z "$output" ]
}

@test "discard requires explicit confirmation and preserves committed history" {
    printf 'committed custom state\n' > "$repo/kept.conf"
    git -C "$repo" add kept.conf
    git -C "$repo" commit -qm 'keep this custom history'
    printf 'uncommitted edit\n' >> "$repo/kept.conf"
    printf 'remove me\n' > "$repo/untracked.conf"
    printf 'keep ignored\n' > "$repo/ignored.conf"

    run run_end4 discard
    [ "$status" -ne 0 ]
    [[ "$output" == *"confirmation requires"* || "$output" == *"discard requires"* ]]
    [ -e "$repo/untracked.conf" ]

    run run_end4 discard --yes
    [ "$status" -eq 0 ]
    [ ! -e "$repo/untracked.conf" ]
    [ -e "$repo/ignored.conf" ]
    [ "$(<"$repo/kept.conf")" = 'committed custom state' ]
    run git -C "$repo" log --format=%s -2
    [[ "$output" == *"keep this custom history"* ]]
}

@test "update dry-run is non-destructive and prune is opt-in" {
    mkdir -p "$home/config/quickshell"
    printf 'live-only\n' > "$home/config/quickshell/live-only.conf"

    run run_end4 update --general --dry-run
    [ "$status" -eq 0 ]
    [ -e "$home/config/quickshell/live-only.conf" ]
    [[ "$output" == *"preserve live extras"* ]]
    [[ "$output" != *"deleting"*"live-only.conf"* ]]

    run run_end4 update --general --prune --dry-run
    [ "$status" -eq 0 ]
    [ -e "$home/config/quickshell/live-only.conf" ]
    [[ "$output" == *"prune extras"* ]]
    [[ "$output" == *"deleting"*"live-only.conf"* ]]
}

@test "update applies a selected device and keeps extras unless prune is requested" {
    mkdir -p "$home/config/quickshell"
    printf 'live-only\n' > "$home/config/quickshell/live-only.conf"

    run run_end4 update --device DarkArch --yes
    [ "$status" -eq 0 ]
    [ -e "$home/config/quickshell/live-only.conf" ]
    [ -e "$home/config/device.conf" ]

    run run_end4 update --general --prune --yes
    [ "$status" -eq 0 ]
    [ ! -e "$home/config/quickshell/live-only.conf" ]
}

@test "system wrapper honors an alternate repository root" {
    run env \
        END4_REPO_ROOT="$repo" \
        HOME="$home" \
        XDG_CONFIG_HOME="$home/config" \
        XDG_DATA_HOME="$home/data" \
        "$BATS_TEST_DIRNAME/../local/.local/bin/system" status

    [ "$status" -eq 0 ]
    [[ "$output" == *"Repository: $repo"* ]]
}

@test "LazyGit configuration exposes the unified command menu" {
    local config_file="$BATS_TEST_DIRNAME/../local/.config/lazygit/config.yml"

    [ -f "$config_file" ]
    grep -q "key: 'S'" "$config_file"
    grep -q "commandMenu:" "$config_file"
    grep -q "end4 merge" "$config_file"
    grep -q "end4 update" "$config_file"
    grep -q "end4 discard" "$config_file"
    grep -q "checkForConflicts: true" "$config_file"
}
