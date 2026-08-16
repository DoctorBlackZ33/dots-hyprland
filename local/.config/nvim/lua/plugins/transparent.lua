return {
  "xiyaowong/transparent.nvim",
  lazy = false,
  config = function()
    require("transparent").setup({
      -- These are the stubborn LazyVim elements
      extra_groups = {
        "NormalFloat",
        "NvimTreeNormal",
        "NeoTreeNormal",
        "NeoTreeNormalNC",
        "TelescopeNormal",
        "TelescopeBorder",
        "TelescopePromptBorder",
        "FloatBorder",
        "WhichKeyFloat",
        "NotifyBackground",
      },
    })
  end,
}
