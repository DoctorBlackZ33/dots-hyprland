-- Keep the Catppuccin configuration in colorscheme.lua untouched. This is a
-- separate colorscheme that owns the generated terminal palette instead of
-- modifying a third-party theme's options.
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    -- Keep Catppuccin installed as the clean fallback. The old hijack remains
    -- in colorscheme.lua for now, but does not affect Catppuccin's active opts.
    opts = function(_, opts)
      opts.custom_highlights = nil
      return opts
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "dynamic",
    },
  },
}
