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
    mkdir -p "$repo/tools"
    cp "$BATS_TEST_DIRNAME/../tools/end4-layout.sh" "$repo/tools/"
    cp "$BATS_TEST_DIRNAME/../tools/end4-dev.sh" "$repo/tools/"
    cp "$BATS_TEST_DIRNAME/../tools/end4-nvim-health.lua" "$repo/tools/"
    cp "$BATS_TEST_DIRNAME/../tools/end4-nvim-sync.lua" "$repo/tools/"
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

make_nvim_source_fixture() {
    mkdir -p \
        "$repo/local/.config/nvim/lua/config" \
        "$repo/local/.config/nvim/lua/plugins"
    printf 'require("config.lazy")\n' > "$repo/local/.config/nvim/init.lua"
    printf '{}\n' > "$repo/local/.config/nvim/lazy-lock.json"
    printf 'return {}\n' > "$repo/local/.config/nvim/lua/codex.lua"
    printf 'return {}\n' > "$repo/local/.config/nvim/lua/plugins/codex.lua"
    printf 'return {}\n' > "$repo/local/.config/nvim/lua/config/lazy.lua"
    printf 'owner=end4_custom\nschema=1\nmode=complete\n' > "$repo/local/.config/nvim/.end4-managed"
    printf '1.4.0\n' > "$repo/local/.config/nvim/codex-acp.version"
}

run_end4_with_path() {
    local prefix="$1"
    shift
    env \
        PATH="$prefix:$PATH" \
        END4_REPO_ROOT="$repo" \
        HOME="$home" \
        XDG_CONFIG_HOME="$home/config" \
        XDG_DATA_HOME="$home/data" \
        END4_FROM_LAZYGIT=1 \
        "$repo/end4" "$@"
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

@test "review gives a structured three-way summary without dumping a raw patch" {
    printf 'fork value\n' > "$repo/review.conf"
    git -C "$repo" add review.conf
    git -C "$repo" commit -qm 'custom review change'
    printf 'upstream value\n' > "$updater/review.conf"
    git -C "$updater" add review.conf
    git -C "$updater" commit -qm 'upstream review change'
    git -C "$updater" push -q origin main

    run run_end4 review

    [ "$status" -eq 0 ]
    [[ "$output" == *"BASE:"* ]]
    [[ "$output" == *"FORK:"* ]]
    [[ "$output" == *"UPSTREAM:"* ]]
    [[ "$output" == *"UC  review.conf"* ]]
    [[ "$output" != *"Full incoming diff"* ]]
    [[ "$output" != *"<<<<<<<"* ]]
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

@test "nvim status identifies recursive live trees and ignores runtime artifacts" {
    make_nvim_source_fixture
    mkdir -p "$home/config/nvim/lua/lua/config" "$home/config/nvim/.backup-themes"
    printf 'recursive\n' > "$home/config/nvim/lua/lua/config/old.lua"
    printf 'log\n' > "$home/config/nvim/nvim.log"
    printf 'backup\n' > "$home/config/nvim/.backup-themes/old.lua"

    run run_end4 nvim status

    [ "$status" -eq 0 ]
    [[ "$output" == *"Recursive Lua trees:"*"cleanup required"* ]]
    [[ "$output" == *"N  lua/lua/config/old.lua"* ]]
    [[ "$output" != *"nvim.log"* ]]
    [[ "$output" != *".backup-themes"* ]]
}

@test "nvim import adopts live files without recursive copying" {
    make_nvim_source_fixture
    mkdir -p "$home/config/nvim/lua/config"
    cp -a "$repo/local/.config/nvim/." "$home/config/nvim/"
    printf 'live-only\n' > "$home/config/nvim/lua/config/live.lua"

    run run_end4 nvim import --yes

    [ "$status" -eq 0 ]
    [ -e "$repo/local/.config/nvim/lua/config/live.lua" ]
    [ ! -e "$repo/local/.config/nvim/lua/lua" ]
}

@test "nvim deployment replaces the live tree and creates a rollback archive" {
    make_nvim_source_fixture
    git -C "$repo" add local/.config/nvim
    git -C "$repo" commit -qm 'fixture complete nvim config'
    mkdir -p "$home/config/nvim"
    cp -a "$repo/local/.config/nvim/." "$home/config/nvim/"
    mkdir -p "$home/config/nvim/lua/lua/config"
    printf 'stale recursive file\n' > "$home/config/nvim/lua/lua/config/stale.lua"
    fake_bin="$test_root/fake-bin"
    mkdir -p "$fake_bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/nvim"
    chmod +x "$fake_bin/nvim"

    run run_end4_with_path "$fake_bin" update --general --yes

    [ "$status" -eq 0 ]
    [ -e "$home/config/nvim/init.lua" ]
    [ -e "$home/config/nvim/.end4-managed" ]
    [ ! -e "$home/config/nvim/lua/lua" ]
    [ -n "$(find "$home/.local/state/end4/backups/nvim" -name config.tar.gz -print -quit)" ]
    [[ "$output" == *"rollback archive"* ]]

    run run_end4_with_path "$fake_bin" nvim rollback --yes

    [ "$status" -eq 0 ]
    [ -e "$home/config/nvim/lua/lua/config/stale.lua" ]
}

@test "nvim check refuses an incomplete repository tree" {
    mkdir -p "$repo/local/.config/nvim/lua/config"

    run run_end4 nvim check

    [ "$status" -ne 0 ]
    [[ "$output" == *"repository Neovim tree is incomplete; missing init.lua"* ]]
}

@test "scoped nvim deploy ignores unrelated dirty repository paths" {
    make_nvim_source_fixture
    git -C "$repo" add local/.config/nvim
    git -C "$repo" commit -qm 'fixture committed nvim config'
    printf 'unrelated user change\n' > "$repo/dots/.config/hypr/unrelated.py"
    fake_bin="$test_root/fake-bin"
    mkdir -p "$fake_bin"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$fake_bin/nvim"
    chmod +x "$fake_bin/nvim"

    run run_end4_with_path "$fake_bin" nvim deploy --yes

    [ "$status" -eq 0 ]
    [ -e "$home/config/nvim/.end4-managed" ]
    [ -e "$repo/dots/.config/hypr/unrelated.py" ]
}

@test "dev mode links managed files, preserves extras, and restores stable live state" {
    mkdir -p "$home/config/hypr/custom" "$home/config/quickshell/ii"
    printf 'stable live value\n' > "$home/config/hypr/custom/general.lua"
    printf 'live extra\n' > "$home/config/quickshell/ii/live-extra.conf"

    run run_end4 dev start feature/live --no-watch --yes

    [ "$status" -eq 0 ]
    worktree="$(git -C "$repo" worktree list --porcelain | awk -v root="$repo" '
        /^worktree / { path=substr($0, 10) }
        /^branch refs\/heads\/feature\/live$/ && path != root { print path; exit }
    ')"
    [ -n "$worktree" ]
    [ -L "$home/config/hypr/custom/general.lua" ]
    [ "$(readlink "$home/config/hypr/custom/general.lua")" = "$worktree/dots/.config/hypr/custom/general.lua" ]
    [ -e "$home/config/quickshell/ii/live-extra.conf" ]

    printf 'experimental live value\n' > "$home/config/hypr/custom/general.lua"
    [ "$(<"$worktree/dots/.config/hypr/custom/general.lua")" = 'experimental live value' ]

    run run_end4 dev stop --yes

    [ "$status" -eq 0 ]
    [ "$(<"$home/config/hypr/custom/general.lua")" = 'stable live value' ]
    [ ! -L "$home/config/hypr/custom/general.lua" ]
    [ "$(<"$home/config/quickshell/ii/live-extra.conf")" = 'live extra' ]
    [[ "$output" == *"Snapshot retained"* ]]
}

@test "dev capture adopts live-only files into the local overlay" {
    mkdir -p "$home/config/quickshell/ii" "$home/config/hypr"
    printf 'capture me\n' > "$home/config/quickshell/ii/captured.conf"
    printf 'monitor capture\n' > "$home/config/hypr/monitors.conf"

    run run_end4 dev start feature/capture --no-watch --yes
    [ "$status" -eq 0 ]
    worktree="$(git -C "$repo" worktree list --porcelain | awk -v root="$repo" '
        /^worktree / { path=substr($0, 10) }
        /^branch refs\/heads\/feature\/capture$/ && path != root { print path; exit }
    ')"
    [ -n "$worktree" ]

    run run_end4 dev capture --yes

    [ "$status" -eq 0 ]
    [ -f "$worktree/local/.config/quickshell/ii/captured.conf" ]
    [ -f "$worktree/local/.config/hypr/monitors.conf" ]
    [ -L "$home/config/quickshell/ii/captured.conf" ]
    [ -L "$home/config/hypr/monitors.conf" ]
    [ "$(<"$worktree/local/.config/quickshell/ii/captured.conf")" = 'capture me' ]
    [ "$(<"$worktree/local/.config/hypr/monitors.conf")" = 'monitor capture' ]

    run run_end4 dev stop --keep --yes

    [ "$status" -eq 0 ]
    [ ! -L "$home/config/quickshell/ii/captured.conf" ]
    [ ! -L "$home/config/hypr/monitors.conf" ]
    [ "$(<"$home/config/quickshell/ii/captured.conf")" = 'capture me' ]
    [ "$(<"$home/config/hypr/monitors.conf")" = 'monitor capture' ]
}

@test "normal deployment is blocked while a development session is attached" {
    run run_end4 dev start feature/guard --no-watch --yes
    [ "$status" -eq 0 ]

    run run_end4 update --general --dry-run

    [ "$status" -ne 0 ]
    [[ "$output" == *"linked development session is active"* ]]

    run run_end4 dev stop --yes
    [ "$status" -eq 0 ]
}

@test "guided development integration prepares a non-committing merge" {
    run run_end4 dev start feature/integrate --no-watch --yes
    [ "$status" -eq 0 ]
    worktree="$(git -C "$repo" worktree list --porcelain | awk -v root="$repo" '
        /^worktree / { path=substr($0, 10) }
        /^branch refs\/heads\/feature\/integrate$/ && path != root { print path; exit }
    ')"
    [ -n "$worktree" ]
    printf 'return { feature = true }\n' > "$worktree/dots/.config/hypr/custom/general.lua"
    git -C "$worktree" add dots/.config/hypr/custom/general.lua
    git -C "$worktree" commit -qm 'feature change'

    run run_end4 dev integrate feature/integrate --yes

    [ "$status" -eq 0 ]
    integration_output="$output"
    [ -e "$repo/.git/MERGE_HEAD" ]
    run git -C "$repo" diff --cached --name-only
    [[ "$output" == *"dots/.config/hypr/custom/general.lua"* ]]
    [[ "$integration_output" == *"feature/integrate"* ]]

    run run_end4 discard --yes
    [ "$status" -eq 0 ]
    run run_end4 dev remove feature/integrate --yes
    [ "$status" -eq 0 ]
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
    grep -q "key: '<c-g>'" "$config_file"
    grep -q "commandMenu:" "$config_file"
    grep -q "end4 review" "$config_file"
    grep -q "end4 merge" "$config_file"
    grep -q "end4 update" "$config_file"
    grep -q "end4 discard" "$config_file"
    grep -q "end4 dev status" "$config_file"
    grep -q "end4 dev capture" "$config_file"
    grep -q "end4 dev stop --keep" "$config_file"
    grep -q "checkForConflicts: true" "$config_file"
}
