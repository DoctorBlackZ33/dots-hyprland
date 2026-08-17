return {
  "folke/which-key.nvim",
  opts = function(_, opts)
    opts.spec = opts.spec or {}
    vim.list_extend(opts.spec, {
      { "<leader>a", group = "Actions", icon = "󰌌" },
      { "<leader>i", group = "IDE", icon = "" },
      { "<leader>j", group = "Java", icon = "" },
      { "<leader>k", group = "Kubernetes", icon = "󱃾" },
      { "<leader>o", group = "Overseer", icon = "󰒲" },
      { "<leader>r", group = "Remote", icon = "󰢹" },
      { "<leader>y", group = "YAML", icon = "󰈙" },
      { "<leader>z", group = "Codex", icon = "󰚩" },
    })
    return opts
  end,
}
