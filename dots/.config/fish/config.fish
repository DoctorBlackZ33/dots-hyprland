function fish_prompt -d "Write out the prompt"
    # This shows up as USER@HOST /home/user/ >, with the directory colored
    # $USER and $hostname are set by fish, so you can just use them
    # instead of using `whoami` and `hostname`
    printf '%s@%s %s%s%s > ' $USER $hostname \
        (set_color $fish_color_cwd) (prompt_pwd) (set_color normal)
end

if status is-interactive # Commands to run in interactive sessions can go here

    # Variables
    set -gx EDITOR nvim
    set -gx VISUAL nvim
    set -gx COLORTERM truecolor
    set -gx TERM xterm-kitty
    set fish_greeting

    # Add local venv bin to PATH
    set -gx PATH "$HOME/.local/bin" $PATH

    # init
    source /usr/share/aur-scan/integration.fish
    zoxide init fish | source
    alias cd z
    tv init fish | source
    # Use starship
    starship init fish | source
    if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
        cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    end

    # Aliases
    alias clear "printf '\033[2J\033[3J\033[1;1H'" # fix: kitty doesn't clear properly
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    function ls --wraps eza --description 'alias ls=eza --icons'
        eza $argv --icons
    end
    alias pamcan pacman
    alias q 'qs -c ii'
    alias sbb sbb-tui
    alias lg lazygit
    # bindings
    bind \cx 'y; commandline -f repaint'
    bind \cw nvim
end
