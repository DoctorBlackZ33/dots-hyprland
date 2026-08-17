#!/usr/bin/env bash

# The repository-to-live mapping is shared by normal deployment and the
# linked development workflow.  The caller must define repo_root,
# config_root, data_root, user_home, and device_name before sourcing this file.

end4_layout_for_each_group() {
    local group="$1"
    local callback="$2"
    local source_entry source_name

    case "$group" in
        upstream)
            shopt -s nullglob
            for source_entry in "$repo_root/dots/.config"/*; do
                source_name="$(basename "$source_entry")"
                case "$source_name" in
                    quickshell|fish|hypr|fontconfig) continue ;;
                esac
                "$callback" "$source_entry" "$config_root/$source_name" upstream-entry
            done
            shopt -u nullglob

            "$callback" "$repo_root/dots/.config/quickshell" "$config_root/quickshell" upstream-quickshell
            "$callback" "$repo_root/dots/.config/fish" "$config_root/fish" upstream-fish
            "$callback" "$repo_root/dots/.config/fontconfig" "$config_root/fontconfig" upstream-fontconfig
            "$callback" "$repo_root/dots/.config/hypr/hyprland" "$config_root/hypr/hyprland" upstream-hyprland
            "$callback" "$repo_root/dots/.config/hypr/custom" "$config_root/hypr/custom" upstream-hypr-custom
            "$callback" "$repo_root/dots/.config/hypr/hyprland.lua" "$config_root/hypr/hyprland.lua" upstream-file
            "$callback" "$repo_root/dots/.config/hypr/hyprlock.conf" "$config_root/hypr/hyprlock.conf" upstream-file
            "$callback" "$repo_root/dots/.config/hypr/hypridle.conf" "$config_root/hypr/hypridle.conf" upstream-file

            # Top-level Hypr helpers are intentionally mapped as files.  This
            # prevents new source files from becoming invisible to deploy or
            # dev mode simply because they are outside hypr/custom.
            shopt -s nullglob
            for source_entry in "$repo_root/dots/.config/hypr"/*; do
                [[ -f "$source_entry" ]] || continue
                source_name="$(basename "$source_entry")"
                case "$source_name" in
                    hyprland.lua|hyprlock.conf|hypridle.conf) continue ;;
                esac
                "$callback" "$source_entry" "$config_root/hypr/$source_name" upstream-file
            done
            shopt -u nullglob

            if [[ -d "$repo_root/dots/.local/share/konsole" ]]; then
                "$callback" "$repo_root/dots/.local/share/konsole" "$data_root/konsole" upstream-data
            fi
            if [[ -f "$repo_root/dots/.local/share/icons/illogical-impulse.svg" ]]; then
                "$callback" "$repo_root/dots/.local/share/icons/illogical-impulse.svg" \
                    "$data_root/icons/illogical-impulse.svg" upstream-data-file
            fi
            ;;
        local)
            if [[ -d "$repo_root/local/.config" ]]; then
                "$callback" "$repo_root/local/.config" "$config_root" local-config
            fi
            if [[ -d "$repo_root/local/.config/nvim" ]]; then
                "$callback" "$repo_root/local/.config/nvim" "$config_root/nvim" local-nvim
            fi
            if [[ -d "$repo_root/local/.local" ]]; then
                "$callback" "$repo_root/local/.local" "$user_home/.local" local-data
            fi
            ;;
        device)
            if [[ -n "$device_name" && -d "$repo_root/devices/$device_name/.config" ]]; then
                "$callback" "$repo_root/devices/$device_name/.config" "$config_root" device-config
            fi
            ;;
        *)
            printf 'end4: unknown layout group: %s\n' "$group" >&2
            return 2
            ;;
    esac
}
