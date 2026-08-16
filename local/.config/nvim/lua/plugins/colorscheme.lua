return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = function()
      -- Safely attempt to load the dynamically generated colors
      local ok, dynamic = pcall(require, "config.dynamic_colors")
      if not ok then
        dynamic = {} -- Fallback if the bash script hasn't run yet
      end

      return {
        transparent_background = true,
        flavor = "mocha",

        -- This is where we hijack the UI without touching syntax
        custom_highlights = function(colors)
          return {
            -- ==========================================
            -- CURRENT LINE HIGHLIGHTING
            -- ==========================================
            -- OPTION A: The Transparent Underline (Highly Recommended)
            -- Keeps the blur intact but draws a colored line under the active row
            CursorLine = { bg = "NONE", underline = true, sp = dynamic.term4 or colors.blue },

            -- OPTION B: The Solid Fill
            -- If you prefer a classic solid dark block (blocks blur on this row),
            -- comment out Option A above and uncomment the line below:
            -- CursorLine = { bg = dynamic.term0 or colors.surface0 },

            -- Make the active line number pop with your accent color
            CursorLineNr = { fg = dynamic.term4 or colors.blue, style = { "bold" } },

            -- ==========================================
            -- POPUPS AND BORDERS
            -- ==========================================
            -- Standard Floating Windows
            NormalFloat = { bg = "NONE" },
            FloatBorder = { fg = dynamic.term15 or colors.overlay0, bg = "NONE" },

            -- Fix Missing Borders on Lazy (Config) and Mason UIs
            LazyNormal = { bg = "NONE" },
            LazyBorder = { fg = dynamic.term4 or colors.blue, bg = "NONE" },
            MasonNormal = { bg = "NONE" },
            MasonBorder = { fg = dynamic.term4 or colors.blue, bg = "NONE" },

            -- Telescope (Fuzzy Finder)
            TelescopeNormal = { bg = "NONE" },
            TelescopeBorder = { fg = dynamic.term4 or colors.blue, bg = "NONE" },

            -- Window Separators
            WinSeparator = { fg = dynamic.term8 or colors.surface1, bg = "NONE" },
          }
        end,
      }
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
