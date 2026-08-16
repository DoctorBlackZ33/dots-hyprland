return {
  {
    "olimorris/codecompanion.nvim",
    lazy = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    opts = function()
      return require("codex").codecompanion_opts()
    end,
    config = function(_, opts)
      require("codecompanion").setup(opts)
      require("codex").setup()
    end,
  },
}
