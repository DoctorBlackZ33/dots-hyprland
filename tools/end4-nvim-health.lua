local delay = tonumber(vim.env.END4_NVIM_HEALTH_DELAY or "2500") or 2500
local failures = 0

local function report(message)
  io.stdout:write(message .. "\n")
  io.stdout:flush()
end

local function check(label, callback)
  local ok, result = pcall(callback)
  if ok then
    report("end4 nvim: PASS " .. label)
    return result
  end

  failures = failures + 1
  report("end4 nvim: FAIL " .. label .. ": " .. tostring(result))
  return nil
end

local function command_exists(name)
  return vim.fn.exists(":" .. name) == 2
end

vim.defer_fn(function()
  check("codex module", function()
    assert(type(require("codex")) == "table")
  end)

  check("codecompanion module", function()
    assert(type(require("codecompanion")) == "table")
  end)

  check("Codex commands", function()
    for _, name in ipairs({
      "CodexChat",
      "CodexAsk",
      "CodexFix",
      "CodexResearch",
      "CodexResearchPreview",
    }) do
      assert(command_exists(name), "missing :" .. name)
    end
  end)

  check("CodeCompanion command", function()
    assert(command_exists("CodeCompanion"), "missing :CodeCompanion")
  end)

  check("Codex keymaps", function()
    for _, mapping in ipairs({
      { mode = "n", lhs = "<leader>zc", desc = "Codex Chat" },
      { mode = "n", lhs = "<leader>za", desc = "Codex Ask" },
      { mode = "n", lhs = "<leader>zf", desc = "Codex Quick Fix" },
      { mode = "n", lhs = "<leader>zr", desc = "Codex Research" },
      { mode = "n", lhs = "<leader>zR", desc = "Preview Codex Research" },
      { mode = "v", lhs = "<leader>za", desc = "Codex Ask Selection" },
      { mode = "v", lhs = "<leader>zf", desc = "Codex Fix Selection" },
    }) do
      local keymap = vim.fn.maparg(mapping.lhs, mapping.mode, false, true)
      assert(type(keymap) == "table" and keymap.lhs ~= "", "missing " .. mapping.mode .. " " .. mapping.lhs)
      assert(keymap.desc == mapping.desc, "unexpected description for " .. mapping.lhs)
    end
  end)

  check("Codex executable", function()
    local path = vim.env.CODEX_PATH or vim.fn.exepath("codex")
    assert(path ~= "", "codex is not on PATH and CODEX_PATH is unset")
    assert(vim.fn.executable(path) == 1, "Codex executable is not executable: " .. path)
  end)

  check("Codex adapter", function()
    local codex = require("codex")
    local options = codex.codecompanion_opts()
    assert(options.adapters and options.adapters.acp, "ACP adapters are missing")
    assert(type(options.adapters.acp.codex) == "function", "Codex ACP adapter is missing")
    assert(options.adapters.acp.codex() ~= nil, "Codex ACP adapter could not be constructed")
  end)

  if failures > 0 then
    vim.cmd("cquit 1")
  else
    vim.cmd("qa!")
  end
end, delay)
