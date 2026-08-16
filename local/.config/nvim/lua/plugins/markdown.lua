local function toggle_checkbox()
  local line = vim.api.nvim_get_current_line()

  local function replace_state(prefix, state)
    return prefix .. "[" .. (state == " " and "x" or " ") .. "]"
  end

  local updated, count = line:gsub("^(%s*[-*+]%s+)%[([ xX])%]", replace_state, 1)
  if count == 0 then
    updated, count = line:gsub("^(%s*%d+[.)]%s+)%[([ xX])%]", replace_state, 1)
  end

  if count > 0 then
    vim.api.nvim_set_current_line(updated)
  end
end

return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    init = function()
      local group = vim.api.nvim_create_augroup("user_markdown", { clear = true })

      vim.api.nvim_create_autocmd("FileType", {
        group = group,
        pattern = { "markdown", "markdown.mdx" },
        callback = function(event)
          vim.opt_local.wrap = true
          vim.opt_local.linebreak = true
          vim.opt_local.breakindent = true
          vim.opt_local.spell = true
          vim.opt_local.conceallevel = 2

          vim.keymap.set("n", "<leader>mx", toggle_checkbox, {
            buffer = event.buf,
            desc = "Toggle Markdown checkbox",
          })
        end,
      })
    end,
    opts = function(_, opts)
      opts = opts or {}
      opts.checkbox = vim.tbl_deep_extend("force", opts.checkbox or {}, {
        enabled = true,
      })
      opts.completions = vim.tbl_deep_extend("force", opts.completions or {}, {
        lsp = { enabled = true },
      })
      return opts
    end,
  },
  {
    "iamcco/markdown-preview.nvim",
    init = function()
      vim.g.mkdp_filetypes = { "markdown", "markdown.mdx" }
      -- CodeCompanion research buffers are Markdown-backed nofile buffers.
      -- Allow the preview command there so Mermaid blocks can be rendered in
      -- the browser without adding another diagram plugin.
      vim.g.mkdp_command_for_global = 1
      vim.g.mkdp_preview_options = {
        mkit = {},
        katex = {},
        uml = {},
        maid = {
          theme = "dark",
        },
        disable_sync_scroll = 0,
        sync_scroll_type = "middle",
        hide_yaml_meta = 1,
        sequence_diagrams = {},
        flowchart_diagrams = {},
        content_editable = false,
        disable_filename = 0,
        toc = {},
      }
      vim.g.mkdp_auto_start = 0
      vim.g.mkdp_auto_close = 1
      vim.g.mkdp_refresh_slow = 0
    end,
  },
}
