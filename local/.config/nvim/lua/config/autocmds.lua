-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Hyprland 0.55+ uses Lua. Keep legacy hyprlang files useful as well, so
-- hyprls and the hyprlang treesitter parser activate for explicit Hyprland
-- configuration files without claiming every .conf file on the system.
vim.filetype.add({
  extension = {
    hypr = "hyprlang",
    hyprlang = "hyprlang",
  },
  filename = {
    ["hyprland.conf"] = "hyprlang",
  },
  pattern = {
    [".*/hyprland%.conf"] = "hyprlang",
  },
})

-- Register IDE task commands as soon as LazyVim loads the user config. This
-- keeps them available even when Neovim opens a file before VeryLazy fires.
require("config.tasks").setup()
require("config.remote").setup()
