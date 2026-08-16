-- Keep LazyVim's Lualine content, but make its own section highlights use
-- the generated dynamic-rice palette and transparent backgrounds.
return {
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.theme = {
        normal = {
          a = "DynamicStatusLineNormal",
          b = "DynamicStatusLineMuted",
          c = "DynamicStatusLine",
        },
        insert = {
          a = "DynamicStatusLineInsert",
          b = "DynamicStatusLineMuted",
          c = "DynamicStatusLine",
        },
        visual = {
          a = "DynamicStatusLineVisual",
          b = "DynamicStatusLineMuted",
          c = "DynamicStatusLine",
        },
        replace = {
          a = "DynamicStatusLineReplace",
          b = "DynamicStatusLineMuted",
          c = "DynamicStatusLine",
        },
        command = {
          a = "DynamicStatusLineCommand",
          b = "DynamicStatusLineMuted",
          c = "DynamicStatusLine",
        },
        terminal = {
          a = "DynamicStatusLineTerminal",
          b = "DynamicStatusLineMuted",
          c = "DynamicStatusLine",
        },
        inactive = {
          a = "DynamicStatusLineInactive",
          b = "DynamicStatusLineInactive",
          c = "DynamicStatusLineInactive",
        },
      }
      opts.options.component_separators = ""
      opts.options.section_separators = ""
      return opts
    end,
  },
}
