-- Generated-palette colorscheme.
--
-- The palette is intentionally read at colorscheme-load time so a generator
-- can replace config.dynamic_colors and the scheme can be reloaded with:
--   :colorscheme dynamic
--
-- Catppuccin remains the fallback when the generated palette is unavailable.

package.loaded["config.dynamic_colors"] = nil

local ok, dynamic = pcall(require, "config.dynamic_colors")
if not ok or type(dynamic) ~= "table" or not dynamic.term0 then
  vim.cmd.colorscheme("catppuccin")
  vim.g.colors_name = "catppuccin-mocha"
  return
end

vim.cmd("highlight clear")
if vim.fn.exists("syntax_on") == 1 then
  vim.cmd("syntax reset")
end

vim.g.colors_name = "dynamic"

local c = {
  bg = dynamic.term0,
  muted = dynamic.term8,
  purple = dynamic.term1,
  green = dynamic.term2,
  pale = dynamic.term3,
  blue = dynamic.term4,
  lavender = dynamic.term5,
  teal = dynamic.term6,
  fg = dynamic.term7,
  bright = dynamic.term15,
  red = dynamic.term9,
  yellow = dynamic.term11,
}

-- dynamic-rice applies term0..term15 as the terminal's ANSI palette. Since
-- options.lua intentionally disables termguicolors, every generated color
-- must also be assigned to its matching cterm index or Neovim renders white.
local cterm_by_hex = {}
for index = 0, 15 do
  local value = dynamic["term" .. index]
  -- Prefer the first matching slot. dynamic-rice commonly aliases bright
  -- colors (term9..term14) to term1..term6; using the last match would make
  -- base syntax colors unexpectedly use the bright indexes.
  if type(value) == "string" and cterm_by_hex[value:upper()] == nil then
    cterm_by_hex[value:upper()] = index
  end
end

local function cterm_index(value)
  if value == "NONE" then
    return "NONE"
  end
  return type(value) == "string" and cterm_by_hex[value:upper()] or nil
end

local function hi(group, value)
  local spec = vim.tbl_extend("force", {}, value)
  if spec.fg and spec.ctermfg == nil then
    spec.ctermfg = cterm_index(spec.fg)
  end
  if spec.bg and spec.ctermbg == nil then
    spec.ctermbg = cterm_index(spec.bg)
  end
  vim.api.nvim_set_hl(0, group, spec)
end

local transparent = { bg = "NONE" }

-- Editor and window chrome.
hi("Normal", { fg = c.fg, bg = "NONE" })
hi("NormalNC", { fg = c.fg, bg = "NONE" })
hi("NormalFloat", { fg = c.fg, bg = "NONE" })
hi("SignColumn", transparent)
hi("FoldColumn", transparent)
hi("EndOfBuffer", { fg = c.muted, bg = "NONE" })
hi("LineNr", { fg = c.muted, bg = "NONE" })
hi("CursorLine", { bg = "NONE", underline = true, sp = c.blue })
hi("CursorLineNr", { fg = c.blue, bg = "NONE", bold = true })
hi("CursorColumn", { bg = c.bg })
hi("ColorColumn", { bg = c.bg })
hi("WinSeparator", { fg = c.muted, bg = "NONE" })
hi("VertSplit", { fg = c.muted, bg = "NONE" })
hi("StatusLine", { fg = c.fg, bg = "NONE" })
hi("StatusLineNC", { fg = c.muted, bg = "NONE" })
hi("TabLine", { fg = c.muted, bg = "NONE" })
hi("TabLineFill", transparent)
hi("TabLineSel", { fg = c.bright, bg = c.bg, bold = true })

-- Lualine creates its own highlight groups instead of using StatusLine.
-- Keep those groups transparent too, while retaining mode-aware palette
-- colors. The groups are linked by the Lualine spec so reloading this scheme
-- after dynamic-rice regenerates the palette updates the bar as well.
hi("DynamicStatusLine", { fg = c.fg, bg = "NONE" })
hi("DynamicStatusLineMuted", { fg = c.muted, bg = "NONE" })
hi("DynamicStatusLineNormal", { fg = c.blue, bg = "NONE", bold = true })
hi("DynamicStatusLineInsert", { fg = c.green, bg = "NONE", bold = true })
hi("DynamicStatusLineVisual", { fg = c.lavender, bg = "NONE", bold = true })
hi("DynamicStatusLineReplace", { fg = c.red, bg = "NONE", bold = true })
hi("DynamicStatusLineCommand", { fg = c.yellow, bg = "NONE", bold = true })
hi("DynamicStatusLineTerminal", { fg = c.teal, bg = "NONE", bold = true })
hi("DynamicStatusLineInactive", { fg = c.muted, bg = "NONE" })

-- Menus, selections, search, and floating borders.
hi("Visual", { bg = c.muted, fg = c.bright })
hi("Search", { fg = c.bg, bg = c.yellow, bold = true })
hi("IncSearch", { fg = c.bg, bg = c.blue, bold = true })
hi("CurSearch", { fg = c.bg, bg = c.blue, bold = true })
hi("MatchParen", { fg = c.blue, bold = true, underline = true })
hi("Pmenu", { fg = c.fg, bg = c.bg })
hi("PmenuSel", { fg = c.bright, bg = c.muted, bold = true })
hi("PmenuSbar", { bg = c.bg })
hi("PmenuThumb", { bg = c.muted })
hi("FloatBorder", { fg = c.bright, bg = "NONE" })
hi("LazyNormal", transparent)
hi("LazyBorder", { fg = c.blue, bg = "NONE" })
hi("MasonNormal", transparent)
hi("MasonBorder", { fg = c.blue, bg = "NONE" })
hi("TelescopeNormal", transparent)
hi("TelescopeBorder", { fg = c.bright, bg = "NONE" })

-- Diagnostics and diff signs.
hi("DiagnosticError", { fg = c.red })
hi("DiagnosticWarn", { fg = c.yellow })
hi("DiagnosticInfo", { fg = c.teal })
hi("DiagnosticHint", { fg = c.green })
hi("DiagnosticUnderlineError", { undercurl = true, sp = c.red })
hi("DiagnosticUnderlineWarn", { undercurl = true, sp = c.yellow })
hi("DiagnosticUnderlineInfo", { undercurl = true, sp = c.teal })
hi("DiagnosticUnderlineHint", { undercurl = true, sp = c.green })
hi("diffAdded", { fg = c.green })
hi("diffChanged", { fg = c.blue })
hi("diffRemoved", { fg = c.red })
hi("GitSignsAdd", { fg = c.green })
hi("GitSignsChange", { fg = c.blue })
hi("GitSignsDelete", { fg = c.red })

-- Vim syntax groups.
hi("Comment", { fg = c.muted, italic = true })
hi("Constant", { fg = c.lavender })
hi("String", { fg = c.green })
hi("Character", { fg = c.green })
hi("Number", { fg = c.pale })
hi("Boolean", { fg = c.pale })
hi("Float", { fg = c.pale })
hi("Identifier", { fg = c.fg })
hi("Function", { fg = c.blue })
hi("Statement", { fg = c.purple, bold = true })
hi("Conditional", { fg = c.purple })
hi("Repeat", { fg = c.purple })
hi("Label", { fg = c.teal })
hi("Operator", { fg = c.teal })
hi("Keyword", { fg = c.purple })
hi("Exception", { fg = c.red })
hi("PreProc", { fg = c.teal })
hi("Include", { fg = c.teal })
hi("Define", { fg = c.teal })
hi("Macro", { fg = c.teal })
hi("Type", { fg = c.yellow })
hi("StorageClass", { fg = c.yellow })
hi("Structure", { fg = c.yellow })
hi("Typedef", { fg = c.yellow })
hi("Special", { fg = c.lavender })
hi("SpecialChar", { fg = c.lavender })
hi("Tag", { fg = c.blue })
hi("Delimiter", { fg = c.fg })
hi("Error", { fg = c.red, bold = true })
hi("Todo", { fg = c.bg, bg = c.yellow, bold = true })

-- Common Treesitter captures.
local links = {
  ["@comment"] = "Comment",
  ["@string"] = "String",
  ["@character"] = "Character",
  ["@number"] = "Number",
  ["@boolean"] = "Boolean",
  ["@constant"] = "Constant",
  ["@constant.builtin"] = "Constant",
  ["@variable"] = "Identifier",
  ["@variable.builtin"] = "Special",
  ["@parameter"] = "Identifier",
  ["@function"] = "Function",
  ["@function.call"] = "Function",
  ["@function.builtin"] = "Function",
  ["@method"] = "Function",
  ["@method.call"] = "Function",
  ["@keyword"] = "Keyword",
  ["@keyword.function"] = "Keyword",
  ["@keyword.operator"] = "Operator",
  ["@operator"] = "Operator",
  ["@type"] = "Type",
  ["@type.builtin"] = "Type",
  ["@constructor"] = "Type",
  ["@tag"] = "Tag",
  ["@tag.attribute"] = "Identifier",
  ["@tag.delimiter"] = "Delimiter",
  ["@punctuation.delimiter"] = "Delimiter",
  ["@punctuation.bracket"] = "Delimiter",
  ["@markup.heading"] = "Title",
  ["@markup.link"] = "Underlined",
}

for group, target in pairs(links) do
  hi(group, { link = target })
end

hi("Title", { fg = c.blue, bold = true })
hi("Underlined", { fg = c.blue, underline = true })
