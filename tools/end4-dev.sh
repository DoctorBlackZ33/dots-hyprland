#!/usr/bin/env bash
set -euo pipefail

script_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/$(basename -- "${BASH_SOURCE[0]}")"
control_repo="${END4_REPO_ROOT:?END4_REPO_ROOT is required}"
user_home="${HOME:?HOME is required}"
config_root="${END4_CONFIG_ROOT:-${XDG_CONFIG_HOME:-$user_home/.config}}"
data_root="${END4_DATA_ROOT:-${XDG_DATA_HOME:-$user_home/.local/share}}"
state_root="${END4_STATE_ROOT:-${XDG_STATE_HOME:-$user_home/.local/state}}"
dev_root="$state_root/end4/dev"
worktree_root="$state_root/end4/worktrees"
session_file="$dev_root/session"
assume_yes=false
watch_enabled=true
device_name=''
from_ref=HEAD

repo_root="$control_repo"
layout_file="$repo_root/tools/end4-layout.sh"
[[ -f "$layout_file" ]] || {
    printf 'end4 dev: shared deployment layout is missing: %s\n' "$layout_file" >&2
    exit 1
}
# shellcheck source=/dev/null
source "$layout_file"

die() {
    printf 'end4 dev: %s\n' "$*" >&2
    exit 1
}

has_tty() {
    [[ -t 0 && -t 1 ]]
}

confirm_dev() {
    local prompt="$1"
    [[ "$assume_yes" == true ]] && return 0
    has_tty || die 'confirmation requires an interactive terminal; use --yes only for intentional automation'
    local response
    read -r -p "$prompt [y/N] " response < /dev/tty
    [[ "$response" =~ ^[Yy]([Ee][Ss])?$ ]]
}

session_value() {
    local key="$1"
    [[ -f "$session_file" ]] || return 1
    awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); print; exit }' "$session_file"
}

session_active() {
    local status
    status="$(session_value STATUS 2>/dev/null || true)"
    [[ "$status" == active || "$status" == attaching ]]
}

load_session() {
    session_active || die 'no active development session'
    active_worktree="$(session_value WORKTREE)"
    active_branch="$(session_value BRANCH)"
    session_device="$(session_value DEVICE || true)"
    snapshot_dir="$(session_value SNAPSHOT)"
    manifest_file="$(session_value MANIFEST)"
    candidate_file="$(session_value CANDIDATES)"
    ignored_file="$(session_value IGNORED || true)"
    watch_pid="$(session_value WATCH_PID || true)"
    [[ -d "$active_worktree" ]] || die "active development worktree is missing: $active_worktree"
    [[ -f "$manifest_file" ]] || die "development manifest is missing: $manifest_file"
    repo_root="$active_worktree"
    device_name="$session_device"
}

write_session() {
    local status="$1"
    mkdir -p "$dev_root"
    {
        printf 'VERSION=1\n'
        printf 'STATUS=%s\n' "$status"
        printf 'CONTROL_REPO=%s\n' "$control_repo"
        printf 'WORKTREE=%s\n' "$active_worktree"
        printf 'BRANCH=%s\n' "$active_branch"
        printf 'DEVICE=%s\n' "$session_device"
        printf 'SNAPSHOT=%s\n' "$snapshot_dir"
        printf 'MANIFEST=%s\n' "$manifest_file"
        printf 'CANDIDATES=%s\n' "$candidate_file"
        printf 'IGNORED=%s\n' "$ignored_file"
        printf 'WATCH_PID=%s\n' "${watch_pid:-}"
    } > "$session_file"
}

validate_device() {
    local candidate="$1"
    [[ -z "$candidate" ]] && return 0
    [[ "$candidate" != */* && "$candidate" != . && "$candidate" != .. ]] || \
        die "invalid device overlay name: $candidate"
    [[ -d "$repo_root/devices/$candidate/.config" ]] || \
        die "unknown device overlay: $candidate"
}

worktree_branch() {
    git -C "$1" branch --show-current 2>/dev/null || true
}

resolve_worktree() {
    local requested="$1"
    local current_path='' current_branch=''
    if [[ -d "$requested" ]]; then
        realpath -- "$requested"
        return 0
    fi

    while IFS= read -r line; do
        case "$line" in
            'worktree '*) current_path="${line#worktree }" ;;
            'branch refs/heads/'*)
                current_branch="${line#branch refs/heads/}"
                if [[ "$current_branch" == "$requested" ]]; then
                    printf '%s\n' "$current_path"
                    return 0
                fi
                ;;
        esac
    done < <(git -C "$control_repo" worktree list --porcelain)
    return 1
}

require_valid_worktree() {
    local path="$1"
    [[ -d "$path" ]] || die "worktree is not a directory: $path"
    git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
        die "not a Git worktree: $path"
    [[ -f "$path/tools/end4-layout.sh" ]] || \
        die "worktree is missing tools/end4-layout.sh: $path"
}

source_active_layout() {
    layout_file="$repo_root/tools/end4-layout.sh"
    [[ -f "$layout_file" ]] || die "active worktree is missing shared layout: $layout_file"
    # shellcheck source=/dev/null
    source "$layout_file"
}

manifest_contains_target() {
    local target="$1"
    awk -F '\t' -v wanted="$target" '$2 == wanted { found=1; exit } END { exit !found }' "$manifest_file"
}

snapshot_contains_target() {
    local target="$1"
    [[ -f "$snapshot_dir/targets.tsv" ]] || return 1
    awk -F '\t' -v wanted="$target" '$2 == wanted { found=1; exit } END { exit !found }' \
        "$snapshot_dir/targets.tsv"
}

dev_snapshot_target() {
    local target="$1"
    [[ -n "${snapshot_dir:-}" ]] || die 'development snapshot is not initialized'
    snapshot_contains_target "$target" && return 0

    local id backup state
    id="$(printf '%06d' "$(wc -l < "$snapshot_dir/targets.tsv")")"
    backup="$snapshot_dir/files/$id"
    mkdir -p "$snapshot_dir/files"
    if [[ -e "$target" || -L "$target" ]]; then
        cp -a -- "$target" "$backup"
        state=present
    else
        state=absent
    fi
    printf '%s\t%s\t%s\n' "$id" "$target" "$state" >> "$snapshot_dir/targets.tsv"
}

dev_restore_snapshot_entry() {
    local id="$1"
    local target="$2"
    local state="$3"
    rm -f -- "$target"
    if [[ "$state" == present ]]; then
        mkdir -p "$(dirname -- "$target")"
        cp -a -- "$snapshot_dir/files/$id" "$target"
    fi
}

dev_restore_snapshot() {
    [[ -f "$snapshot_dir/targets.tsv" ]] || return 0
    local -a records=()
    mapfile -t records < "$snapshot_dir/targets.tsv"
    local index id target state
    for ((index=${#records[@]} - 1; index >= 0; index--)); do
        IFS=$'\t' read -r id target state <<< "${records[index]}"
        dev_restore_snapshot_entry "$id" "$target" "$state"
    done
}

dev_preflight_manifest() {
    local manifest="$1"
    [[ -s "$manifest" ]] || die 'active worktree contains no deployable files'
    local duplicate
    duplicate="$(cut -f2 "$manifest" | sort | uniq -d | head -1 || true)"
    [[ -z "$duplicate" ]] || die "deployment layout maps more than one source to: $duplicate"

    local source target kind parent
    while IFS=$'\t' read -r source target kind; do
        [[ -n "$source" ]] || continue
        [[ -f "$source" || -L "$source" ]] || die "mapped source file is missing: $source"
        parent="$(dirname -- "$target")"
        if [[ -e "$parent" && ! -d "$parent" ]]; then
            die "live parent is not a directory: $parent"
        fi
        if [[ -e "$target" && -d "$target" && ! -L "$target" ]]; then
            die "live target is a directory but a file is required: $target"
        fi
    done < "$manifest"
}

dev_emit_file() {
    local source="$1"
    local target="$2"
    local kind="$3"
    local output="$4"

    case "$target" in
        "$config_root/nvim/lua/config/dynamic_colors.lua"|*.log|*/nvim.log)
            return 0
            ;;
    esac
    printf '%s\t%s\t%s\n' "$source" "$target" "$kind" >> "$output"
}

dev_collect_root() {
    local source_root="$1"
    local target_root="$2"
    local kind="$3"
    local output="$4"
    [[ -e "$source_root" || -L "$source_root" ]] || return 0

    if [[ -f "$source_root" || -L "$source_root" ]]; then
        dev_emit_file "$source_root" "$target_root" "$kind" "$output"
        return 0
    fi

    local find_root="$source_root"
    local file relative target
    while IFS= read -r -d '' file; do
        relative="${file#"$find_root"/}"
        target="$target_root/$relative"
        dev_emit_file "$file" "$target" "$kind" "$output"
    done < <(
        case "$kind" in
            upstream-fish)
                find "$source_root" \
                    -path "$source_root/conf.d" -prune -o \
                    -path '*/.git' -prune -o \
                    -path '*/__pycache__' -prune -o \
                    \( -type f -o -type l \) -print0
                ;;
            local-config|device-config)
                find "$source_root" \
                    -path "$source_root/nvim" -prune -o \
                    -path '*/.git' -prune -o \
                    -path '*/__pycache__' -prune -o \
                    \( -type f -o -type l \) -print0
                ;;
            *)
                find "$source_root" \
                    -path '*/.git' -prune -o \
                    -path '*/__pycache__' -prune -o \
                    \( -type f -o -type l \) -print0
                ;;
        esac
    )
}

dev_collect_layout() {
    dev_collect_root "$1" "$2" "$3" "$dev_manifest_work"
}

dev_build_manifest() {
    dev_manifest_work="$1"
    : > "$dev_manifest_work"
    end4_layout_for_each_group upstream dev_collect_layout
    end4_layout_for_each_group local dev_collect_layout
    end4_layout_for_each_group device dev_collect_layout
    sort -u -t $'\t' -k2,2 "$dev_manifest_work" -o "$dev_manifest_work"
}

dev_emit_candidate_root() {
    local source_root="$1"
    local target_root="$2"
    local kind="$3"
    local output="$4"

    local child name
    case "$kind" in
        upstream-quickshell|upstream-fish|upstream-fontconfig|upstream-hyprland|upstream-hypr-custom)
            if [[ ! -d "$source_root" ]]; then
                printf '%s\t%s\t%s\n' "$source_root" "$target_root" "$kind" >> "$output"
                return 0
            fi
            printf '%s\t%s\t%s\n' "$source_root" "$target_root" "$kind" >> "$output"
            ;;
        local-config|local-data|device-config)
            [[ -d "$source_root" ]] || return 0
            while IFS= read -r -d '' child; do
                name="$(basename "$child")"
                [[ "$name" == nvim ]] && continue
                if [[ -d "$child" ]]; then
                    printf '%s\t%s\t%s\n' "$child" "$target_root/$name" "$kind" >> "$output"
                fi
            done < <(find "$source_root" -mindepth 1 -maxdepth 1 -print0)
            ;;
        *)
            [[ -d "$source_root" ]] || return 0
            printf '%s\t%s\t%s\n' "$source_root" "$target_root" "$kind" >> "$output"
            ;;
    esac
}

dev_collect_candidate_layout() {
    dev_emit_candidate_root "$1" "$2" "$3" "$dev_candidate_work"
}

dev_build_candidate_roots() {
    dev_candidate_work="$1"
    : > "$dev_candidate_work"
    end4_layout_for_each_group upstream dev_collect_candidate_layout
    end4_layout_for_each_group local dev_collect_candidate_layout
    end4_layout_for_each_group device dev_collect_candidate_layout
    # The upstream layout manages several Hypr subdirectories and files but
    # intentionally leaves the Hypr root available for user/device extras.
    # Scan that root too so files such as monitors.conf can be classified.
    printf '%s\t%s\tupstream-hypr-root\n' "$repo_root/dots/.config/hypr" "$config_root/hypr" >> "$dev_candidate_work"
    if [[ ! -d "$repo_root/local/.config" ]]; then
        printf '%s\t%s\tlocal-config\n' "$repo_root/local/.config" "$config_root" >> "$dev_candidate_work"
    fi
    if [[ -n "$device_name" && ! -d "$repo_root/devices/$device_name/.config" ]]; then
        printf '%s\t%s\tdevice-config\n' "$repo_root/devices/$device_name/.config" "$config_root" >> "$dev_candidate_work"
    fi
    sort -u -t $'\t' -k2,2 "$dev_candidate_work" -o "$dev_candidate_work"
}

dev_link_manifest() {
    local manifest="$1"
    local source target kind
    while IFS=$'\t' read -r source target kind; do
        [[ -n "$source" ]] || continue
        mkdir -p "$(dirname -- "$target")"
        if [[ -L "$target" && "$(readlink -- "$target")" == "$source" ]]; then
            continue
        fi
        dev_snapshot_target "$target"
        rm -f -- "$target"
        ln -s -- "$source" "$target"
    done < "$manifest"
}

dev_restore_removed_links() {
    local old_manifest="$1"
    local new_manifest="$2"
    [[ -f "$old_manifest" ]] || return 0
    local source target kind
    while IFS=$'\t' read -r source target kind; do
        [[ -n "$target" ]] || continue
        if ! awk -F '\t' -v wanted="$target" '$2 == wanted { found=1; exit } END { exit !found }' "$new_manifest"; then
            local record
            record="$(awk -F '\t' -v wanted="$target" '$2 == wanted { print; exit }' "$snapshot_dir/targets.tsv" 2>/dev/null || true)"
            if [[ -n "$record" ]]; then
                local id old_target state
                IFS=$'\t' read -r id old_target state <<< "$record"
                dev_restore_snapshot_entry "$id" "$old_target" "$state"
            fi
        fi
    done < "$old_manifest"
}

dev_refresh() {
    load_session
    source_active_layout
    local new_manifest="$snapshot_dir/manifest.$$.tsv"
    dev_build_manifest "$new_manifest"
    dev_preflight_manifest "$new_manifest"
    dev_restore_removed_links "$manifest_file" "$new_manifest"
    dev_link_manifest "$new_manifest"
    mv -- "$new_manifest" "$manifest_file"
    dev_build_candidate_roots "$candidate_file"
    write_session active
    printf 'Development links refreshed for %s (%s).\n' "$active_branch" "$active_worktree"
}

dev_is_ignored_candidate() {
    local path="$1"
    case "$path" in
        */.git|*/.git/*|*/__pycache__|*/__pycache__/*|*.pyc|*.log|*/nvim.log|*/nvim/lua/config/dynamic_colors.lua|*/Untitled|*/.backup-themes|*/.backup-themes/*|*/hyprland.bak_*|*/hyprland.bak_*/*)
            return 0
            ;;
    esac
    return 1
}

dev_candidate_is_mapped() {
    local candidate="$1"
    awk -F '\t' -v wanted="$candidate" '$2 == wanted { found=1; exit } END { exit !found }' "$manifest_file"
}

dev_candidate_is_ignored() {
    local candidate="$1"
    [[ -f "$ignored_file" ]] || return 1
    grep -Fqx -- "$candidate" "$ignored_file"
}

dev_find_candidates() {
    load_session
    source_active_layout
    local root_source root_target root_kind file
    local -A seen=()
    dev_candidate_work="$snapshot_dir/candidates.live.tsv"
    : > "$dev_candidate_work"
    while IFS=$'\t' read -r root_source root_target root_kind; do
        [[ -d "$root_target" ]] || continue
        while IFS= read -r -d '' file; do
            [[ -n "${seen[$file]:-}" ]] && continue
            seen["$file"]=1
            dev_is_ignored_candidate "$file" && continue
            dev_candidate_is_mapped "$file" && continue
            dev_candidate_is_ignored "$file" && continue
            printf '%s\t%s\t%s\n' "$file" "$root_target" "$root_kind" >> "$dev_candidate_work"
        done < <(
            find "$root_target" \
                -path '*/.git' -prune -o \
                -path '*/__pycache__' -prune -o \
                \( -type f -o -type l \) -print0
        )
    done < "$candidate_file"
    sort -u -t $'\t' -k1,1 "$dev_candidate_work" -o "$dev_candidate_work"
}

dev_candidate_destination() {
    local candidate="$1"
    local target_root="$2"
    local kind="$3"
    local relative
    relative="${candidate#"$target_root"/}"
    case "$kind" in
        local-nvim)
            printf '%s\n' "$active_worktree/local/.config/nvim/$relative"
            ;;
        local-data)
            printf '%s\n' "$active_worktree/local/.local/$relative"
            ;;
        device-config)
            printf '%s\n' "$active_worktree/devices/$session_device/.config/$relative"
            ;;
        upstream-data|upstream-data-file)
            printf '%s\n' "$active_worktree/local/.local/share/$relative"
            ;;
        *)
            if [[ "$candidate" == "$config_root/"* ]]; then
                printf '%s\n' "$active_worktree/local/.config/${candidate#"$config_root"/}"
            else
                printf '%s\n' "$active_worktree/local/.local/${candidate#"$user_home/.local"/}"
            fi
            ;;
    esac
}

dev_capture() {
    load_session
    source_active_layout
    dev_find_candidates
    if [[ ! -s "$dev_candidate_work" ]]; then
        printf 'No unlinked live files need capture.\n'
        git -C "$active_worktree" status --short --branch
        return 0
    fi

    printf 'Unlinked live files found:\n'
    cut -f1 "$dev_candidate_work"
    if ! has_tty && [[ "$assume_yes" != true ]]; then
        die 'capture needs an interactive terminal to classify live files; use --yes to adopt all safe candidates'
    fi

    local candidate target_root kind answer destination
    while IFS=$'\t' read -r candidate target_root kind; do
        [[ -n "$candidate" ]] || continue
        if [[ "$assume_yes" == true ]]; then
            answer=a
        else
            printf '\nCandidate: %s\n' "$candidate"
            printf '  [a]dopt into the active branch, [i]gnore, or [l]eave untouched? '
            read -r answer < /dev/tty
            answer="${answer:-l}"
        fi
        case "$answer" in
            a|A)
                destination="$(dev_candidate_destination "$candidate" "$target_root" "$kind")"
                if [[ -e "$destination" || -L "$destination" ]]; then
                    die "capture destination already exists; resolve it manually: $destination"
                fi
                mkdir -p "$(dirname -- "$destination")"
                cp -a -- "$candidate" "$destination"
                printf '  adopted -> %s\n' "$destination"
                ;;
            i|I)
                printf '%s\n' "$candidate" >> "$ignored_file"
                printf '  ignored for this development session\n'
                ;;
            l|L) printf '  left untouched\n' ;;
            *) printf '  unrecognized choice; left untouched\n' ;;
        esac
    done < "$dev_candidate_work"
    dev_refresh
    printf '\nActive branch changes:\n'
    git -C "$active_worktree" status --short --branch
}

dev_materialize_current() {
    local source target kind
    while IFS=$'\t' read -r source target kind; do
        [[ -n "$source" ]] || continue
        mkdir -p "$(dirname -- "$target")"
        rm -f -- "$target"
        cp -a -- "$source" "$target"
    done < "$manifest_file"
}

dev_stop_watcher() {
    [[ -n "${watch_pid:-}" ]] || return 0
    if kill -0 "$watch_pid" 2>/dev/null; then
        kill "$watch_pid" 2>/dev/null || true
        wait "$watch_pid" 2>/dev/null || true
    fi
    watch_pid=''
}

dev_stop() {
    load_session
    local keep=false
    if [[ "${1:-}" == --keep ]]; then
        keep=true
    fi
    if [[ "$keep" == true ]]; then
        confirm_dev 'Keep the tested development files as regular live configuration?' || {
            printf 'Development stop cancelled.\n'
            return 0
        }
    else
        confirm_dev 'Restore the stable live configuration and detach the development links?' || {
            printf 'Development stop cancelled.\n'
            return 0
        }
    fi

    dev_stop_watcher
    if [[ "$keep" == true ]]; then
        dev_materialize_current
    else
        dev_restore_snapshot
    fi
    rm -f -- "$session_file"
    printf 'Development session stopped. Snapshot retained at %s\n' "$snapshot_dir"
}

dev_start_watcher() {
    [[ "$watch_enabled" == true ]] || return 0
    if ! command -v inotifywait >/dev/null 2>&1; then
        printf 'Watcher disabled: inotifywait is not installed; use system dev reload explicitly.\n' >&2
        watch_pid=''
        write_session active
        return 0
    fi
    local log_file="$snapshot_dir/watcher.log"
    (bash "$script_path" __watch-loop "$active_worktree" "$log_file") >/dev/null 2>&1 &
    watch_pid=$!
    write_session active
    printf 'Development reload watcher started (PID %s).\n' "$watch_pid"
}

dev_attach_worktree() {
    local path="$1"
    require_valid_worktree "$path"
    [[ "$path" != "$control_repo" ]] || die 'the main worktree cannot be attached as a development worktree'
    session_active && die 'a development session is already active; run system dev stop first'

    active_worktree="$(realpath -- "$path")"
    active_branch="$(worktree_branch "$active_worktree")"
    [[ -n "$active_branch" ]] || die 'development worktree must have a named branch'
    [[ "$active_branch" != main ]] || die 'the main branch cannot be attached for development; use a feature branch'
    session_device="$device_name"
    validate_device "$session_device"
    repo_root="$active_worktree"
    source_active_layout

    local session_stamp slug
    session_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    slug="$(basename -- "$active_worktree")"
    snapshot_dir="$dev_root/snapshots/$session_stamp-$slug"
    manifest_file="$snapshot_dir/manifest.tsv"
    candidate_file="$snapshot_dir/candidates.tsv"
    ignored_file="$snapshot_dir/ignored.txt"
    mkdir -p "$snapshot_dir"
    : > "$snapshot_dir/targets.tsv"
    : > "$ignored_file"

    dev_manifest_work="$snapshot_dir/manifest.new.tsv"
    dev_build_manifest "$dev_manifest_work"
    dev_preflight_manifest "$dev_manifest_work"
    mv -- "$dev_manifest_work" "$manifest_file"
    dev_build_candidate_roots "$candidate_file"
    confirm_dev "Attach $active_branch and replace managed live files with links?" || {
        printf 'Development attachment cancelled.\n'
        rm -rf -- "$snapshot_dir"
        return 1
    }
    write_session attaching

    if ! dev_link_manifest "$manifest_file"; then
        dev_restore_snapshot
        rm -f -- "$session_file"
        die 'development links failed; the pre-session live state was restored'
    fi
    write_session active
    printf 'Development worktree attached:\n  branch:   %s\n  worktree: %s\n' "$active_branch" "$active_worktree"
    printf 'Edit through %s; linked files write directly to this branch.\n' "$config_root"
    dev_start_watcher
}

dev_start() {
    local branch="$1"
    [[ -n "$branch" ]] || die 'dev start requires a branch name'
    session_active && die 'a development session is already active; run system dev stop first'
    git -C "$control_repo" status --porcelain | grep -q . && \
        die 'main worktree is dirty; commit or intentionally discard it before starting development'
    git -C "$control_repo" check-ref-format --branch "$branch" >/dev/null 2>&1 || \
        die "invalid branch name: $branch"
    [[ "$branch" != main ]] || die 'use a feature branch instead of main for development'
    [[ "$from_ref" != '' ]] || from_ref=HEAD

    local slug digest worktree
    slug="$(printf '%s' "$branch" | tr '/ ' '__' | tr -cd '[:alnum:]_.-')"
    digest="$(printf '%s' "$branch" | sha256sum | cut -c1-8)"
    worktree="$worktree_root/${slug:-dev}-$digest"
    [[ ! -e "$worktree" ]] || die "development worktree path already exists: $worktree"
    mkdir -p "$worktree_root"
    git -C "$control_repo" worktree add -b "$branch" "$worktree" "$from_ref"
    if ! dev_attach_worktree "$worktree"; then
        git -C "$control_repo" worktree remove --force "$worktree" >/dev/null 2>&1 || true
        return 1
    fi
}

dev_status() {
    if ! session_active; then
        printf 'No active development session.\n\nAvailable worktrees:\n'
        git -C "$control_repo" worktree list
        return 0
    fi
    load_session
    source_active_layout
    local total=0 linked=0 broken=0 source_missing=0 source target kind
    while IFS=$'\t' read -r source target kind; do
        [[ -n "$source" ]] || continue
        total=$((total + 1))
        if [[ ! -e "$source" && ! -L "$source" ]]; then
            source_missing=$((source_missing + 1))
        elif [[ -L "$target" && "$(readlink -- "$target")" == "$source" ]]; then
            linked=$((linked + 1))
        else
            broken=$((broken + 1))
        fi
    done < "$manifest_file"
    printf 'Development session: active\n'
    printf '  branch:    %s\n' "$active_branch"
    printf '  worktree:  %s\n' "$active_worktree"
    printf '  device:    %s\n' "${session_device:-general}"
    printf '  links:     %d/%d valid\n' "$linked" "$total"
    printf '  broken:    %d\n' "$broken"
    printf '  missing:   %d source files\n' "$source_missing"
    if [[ -n "${watch_pid:-}" ]] && kill -0 "$watch_pid" 2>/dev/null; then
        printf '  watcher:   running (%s)\n' "$watch_pid"
    else
        printf '  watcher:   stopped\n'
    fi
    printf '\nBranch state:\n'
    git -C "$active_worktree" status --short --branch
    dev_find_candidates
    if [[ -s "$dev_candidate_work" ]]; then
        printf '\nUnlinked live candidates (run system dev capture):\n'
        cut -f1 "$dev_candidate_work"
    else
        printf '\nUnlinked live candidates: none\n'
    fi
}

dev_reload() {
    load_session
    local scope="${1:-all}"
    case "$scope" in
        hypr)
            if command -v hyprctl >/dev/null 2>&1; then
                hyprctl reload
            else
                printf 'Hyprland reload skipped: hyprctl is not available.\n'
            fi
            ;;
        quickshell)
            if command -v qs >/dev/null 2>&1; then
                qs -c ii ipc call end4Dev reload || \
                    die 'Quickshell developer IPC is unavailable; deploy the linked shell.qml or restart qs manually'
            else
                printf 'Quickshell reload skipped: qs is not available.\n'
            fi
            ;;
        all)
            dev_reload hypr
            dev_reload quickshell
            ;;
        *)
            die "unknown reload scope: $scope (use hypr, quickshell, or all)"
            ;;
    esac
}

dev_check() {
    load_session
    printf 'Checking active development worktree: %s\n' "$active_worktree"
    env \
        END4_REPO_ROOT="$active_worktree" \
        END4_DEV_INTERNAL=1 \
        XDG_CONFIG_HOME="$config_root" \
        XDG_DATA_HOME="$data_root" \
        XDG_STATE_HOME="$state_root" \
        "$active_worktree/end4" check
}

dev_sync() {
    load_session
    printf 'Synchronizing plugins for active development worktree: %s\n' "$active_worktree"
    env \
        END4_REPO_ROOT="$active_worktree" \
        END4_DEV_INTERNAL=1 \
        XDG_CONFIG_HOME="$config_root" \
        XDG_DATA_HOME="$data_root" \
        XDG_STATE_HOME="$state_root" \
        "$active_worktree/end4" nvim sync
}

dev_launch_lazygit() {
    [[ "${END4_FROM_LAZYGIT:-0}" == 1 ]] && return 0
    has_tty || return 0
    command -v lazygit >/dev/null 2>&1 || {
        printf 'LazyGit is not installed; inspect the prepared merge with Git.\n' >&2
        return 0
    }
    local config_file="$control_repo/local/.config/lazygit/config.yml"
    if [[ -f "$config_file" ]]; then
        lazygit --path "$control_repo" --use-config-file "$config_file" || true
    else
        lazygit --path "$control_repo" || true
    fi
}

dev_integrate() {
    local branch="$1"
    [[ -n "$branch" ]] || die 'dev integrate requires a branch name'
    local worktree
    worktree="$(resolve_worktree "$branch" || true)"
    [[ -n "$worktree" ]] || die "no worktree found for branch: $branch"
    [[ "$worktree" != "$control_repo" ]] || die 'the main worktree cannot be removed'
    [[ "$(worktree_branch "$worktree")" != main ]] || die 'the main branch cannot be removed as a development worktree'
    [[ "$worktree" != "$control_repo" ]] || die 'main is not a development branch'

    if session_active; then
        load_session
        [[ "$active_branch" == "$branch" ]] || die 'another development branch is attached; stop it first'
        dev_capture
        git -C "$active_worktree" status --porcelain | grep -q . && \
            die 'development branch is dirty; review and commit it before integrating'
        dev_stop
    fi

    git -C "$control_repo" branch --show-current | grep -qx main || \
        die 'guided integration must be run from the main worktree'
    git -C "$control_repo" status --porcelain | grep -q . && \
        die 'main worktree is dirty; clean it before integrating a development branch'
    git -C "$control_repo" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 && \
        die 'main already has a merge in progress; resolve or discard it first'
    git -C "$worktree" status --porcelain | grep -q . && \
        die 'development branch is dirty; commit or discard it before integrating'

    env \
        END4_REPO_ROOT="$worktree" \
        END4_DEV_INTERNAL=1 \
        XDG_CONFIG_HOME="$config_root" \
        XDG_DATA_HOME="$data_root" \
        XDG_STATE_HOME="$state_root" \
        "$worktree/end4" check

    confirm_dev "Prepare a non-committing merge of $branch into main?" || {
        printf 'Development integration cancelled.\n'
        return 0
    }
    if git -C "$control_repo" merge --no-ff --no-commit "$branch"; then
        printf 'Development merge prepared and left uncommitted.\n'
    else
        printf 'Development merge stopped with conflicts. Resolve them in LazyGit, then commit or run system discard.\n' >&2
        dev_launch_lazygit
        return 1
    fi
    dev_launch_lazygit
    git -C "$control_repo" status --short --branch
}

dev_remove() {
    local branch="$1"
    local delete_branch=false
    [[ -n "$branch" ]] || die 'dev remove requires a branch name'
    [[ "${2:-}" == --delete-branch ]] && delete_branch=true
    local worktree
    worktree="$(resolve_worktree "$branch" || true)"
    [[ -n "$worktree" ]] || die "no worktree found for branch: $branch"
    session_active && {
        load_session
        [[ "$active_worktree" != "$worktree" ]] || die 'cannot remove the active development worktree; run dev stop first'
    }
    git -C "$worktree" status --porcelain | grep -q . && \
        die 'development worktree is dirty; commit or discard it before removal'
    confirm_dev "Remove development worktree $worktree?" || {
        printf 'Development worktree removal cancelled.\n'
        return 0
    }
    git -C "$control_repo" worktree remove "$worktree"
    if [[ "$delete_branch" == true ]]; then
        confirm_dev "Delete branch $branch as well?" && git -C "$control_repo" branch -d "$branch"
    fi
    printf 'Development worktree removed: %s\n' "$worktree"
}

dev_watch_loop() {
    local worktree="$1"
    local log_file="$2"
    command -v inotifywait >/dev/null 2>&1 || exit 0
    local -a watch_dirs=()
    for path in \
        "$worktree/dots/.config/hypr" \
        "$worktree/dots/.config/quickshell" \
        "$worktree/local/.config"; do
        [[ -d "$path" ]] && watch_dirs+=("$path")
    done
    [[ "${#watch_dirs[@]}" -gt 0 ]] || exit 0
    mkdir -p "$(dirname -- "$log_file")"
    while IFS= read -r changed; do
        case "$changed" in
            */dots/.config/hypr/*)
                sleep 0.35
                if command -v hyprctl >/dev/null 2>&1; then
                    hyprctl reload >>"$log_file" 2>&1 || true
                fi
                ;;
            */dots/.config/quickshell/*)
                sleep 0.35
                if command -v qs >/dev/null 2>&1; then
                    qs -c ii ipc call end4Dev reload >>"$log_file" 2>&1 || true
                fi
                ;;
            */local/.config/nvim/*)
                # Neovim/plugin reloads are intentionally explicit.
                ;;
        esac
    done < <(inotifywait -m -r -e close_write,moved_to,create,delete --format '%w%f' "${watch_dirs[@]}" 2>>"$log_file")
}

subcommand="${1:-status}"
shift || true

case "$subcommand" in
    start)
        branch="${1:-}"
        shift || true
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --from)
                    [[ $# -ge 2 ]] || die '--from requires a Git ref'
                    from_ref="$2"
                    shift 2
                    ;;
                --device)
                    [[ $# -ge 2 ]] || die '--device requires a name'
                    device_name="$2"
                    shift 2
                    ;;
                --no-watch) watch_enabled=false; shift ;;
                --yes) assume_yes=true; shift ;;
                -h|--help) printf 'Usage: system dev start BRANCH [--from REF] [--device NAME] [--no-watch] [--yes]\n'; exit 0 ;;
                *) die "unknown dev start option: $1" ;;
            esac
        done
        dev_start "$branch"
        ;;
    attach)
        requested="${1:-}"
        shift || true
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --device)
                    [[ $# -ge 2 ]] || die '--device requires a name'
                    device_name="$2"
                    shift 2
                    ;;
                --no-watch) watch_enabled=false; shift ;;
                --yes) assume_yes=true; shift ;;
                -h|--help) printf 'Usage: system dev attach BRANCH|WORKTREE [--device NAME] [--no-watch] [--yes]\n'; exit 0 ;;
                *) die "unknown dev attach option: $1" ;;
            esac
        done
        [[ -n "$requested" ]] || die 'dev attach requires a branch or worktree path'
        resolved="$(resolve_worktree "$requested" || true)"
        [[ -n "$resolved" ]] || die "no worktree found for: $requested"
        dev_attach_worktree "$resolved"
        ;;
    status)
        [[ $# -eq 0 ]] || die "unknown dev status option: $1"
        dev_status
        ;;
    refresh)
        [[ $# -eq 0 ]] || die "unknown dev refresh option: $1"
        dev_refresh
        ;;
    capture)
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --yes) assume_yes=true; shift ;;
                -h|--help) printf 'Usage: system dev capture [--yes]\n'; exit 0 ;;
                *) die "unknown dev capture option: $1" ;;
            esac
        done
        dev_capture
        ;;
    reload)
        [[ $# -le 1 ]] || die 'dev reload accepts one scope: hypr, quickshell, or all'
        dev_reload "${1:-all}"
        ;;
    check)
        [[ $# -eq 0 ]] || die "unknown dev check option: $1"
        dev_check
        ;;
    sync)
        [[ $# -eq 0 ]] || die "unknown dev sync option: $1"
        dev_sync
        ;;
    stop)
        [[ $# -le 2 ]] || die 'dev stop accepts --keep and --yes'
        keep_arg=''
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --keep) keep_arg=--keep; shift ;;
                --yes) assume_yes=true; shift ;;
                -h|--help) printf 'Usage: system dev stop [--keep] [--yes]\n'; exit 0 ;;
                *) die "unknown dev stop option: $1" ;;
            esac
        done
        dev_stop "$keep_arg"
        ;;
    integrate)
        branch="${1:-}"
        shift || true
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --yes) assume_yes=true; shift ;;
                -h|--help) printf 'Usage: system dev integrate BRANCH [--yes]\n'; exit 0 ;;
                *) die "unknown dev integrate option: $1" ;;
            esac
        done
        dev_integrate "$branch"
        ;;
    remove)
        branch="${1:-}"
        shift || true
        delete_arg=''
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --delete-branch) delete_arg=--delete-branch; shift ;;
                --yes) assume_yes=true; shift ;;
                -h|--help) printf 'Usage: system dev remove BRANCH [--delete-branch] [--yes]\n'; exit 0 ;;
                *) die "unknown dev remove option: $1" ;;
            esac
        done
        dev_remove "$branch" "$delete_arg"
        ;;
    __watch-loop)
        [[ $# -eq 2 ]] || exit 2
        dev_watch_loop "$1" "$2"
        ;;
    -h|--help)
        printf 'Usage: system dev {start|attach|status|refresh|capture|reload|check|sync|stop|integrate|remove}\n'
        ;;
    *)
        die "unknown dev subcommand: $subcommand"
        ;;
esac
