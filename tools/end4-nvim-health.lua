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

local function mapping(mode, lhs)
  return vim.fn.maparg(lhs, mode, false, true)
end

vim.defer_fn(function()
  local codex = check("codex module", function()
    local module = require("codex")
    assert(type(module) == "table")
    assert(type(module.model_defaults) == "table")
    return module
  end)

  check("codecompanion module", function()
    assert(type(require("codecompanion")) == "table")
  end)

  check("Codex commands", function()
    for _, name in ipairs({
      "CodexChat",
      "CodexChatNew",
      "CodexAsk",
      "CodexFix",
      "CodexResearch",
      "CodexResearchNew",
      "CodexResearchPreview",
      "CodexResearchStop",
      "CodexSessions",
      "CodexSessionPicker",
      "CodexHide",
      "CodexChanges",
    }) do
      assert(command_exists(name), "missing :" .. name)
    end
  end)

  check("CodeCompanion command", function()
    assert(command_exists("CodeCompanion"), "missing :CodeCompanion")
  end)

  check("Codex keymaps", function()
    for _, expected in ipairs({
      { mode = "n", lhs = "<leader>zc", desc = "Codex Chat" },
      { mode = "n", lhs = "<leader>zC", desc = "New Codex Chat" },
      { mode = "n", lhs = "<leader>za", desc = "Codex Ask" },
      { mode = "n", lhs = "<leader>zf", desc = "Codex Quick Fix" },
      { mode = "n", lhs = "<leader>zs", desc = "Codex Research" },
      { mode = "n", lhs = "<leader>zS", desc = "Preview Codex Research" },
      { mode = "n", lhs = "<leader>zr", desc = "Codex Session Picker" },
      { mode = "v", lhs = "<leader>za", desc = "Codex Ask Selection" },
      { mode = "v", lhs = "<leader>zf", desc = "Codex Fix Selection" },
    }) do
      local keymap = mapping(expected.mode, expected.lhs)
      assert(type(keymap) == "table" and keymap.lhs ~= "", "missing " .. expected.mode .. " " .. expected.lhs)
      assert(keymap.desc == expected.desc, "unexpected description for " .. expected.lhs)
    end

    local stale = mapping("n", "<leader>zR")
    assert(
      not stale.lhs or stale.desc ~= "Preview Codex Research",
      "stale <leader>zR Codex mapping is still installed"
    )
  end)

  check("Codex executable", function()
    local path = vim.env.CODEX_PATH or vim.fn.exepath("codex")
    assert(path ~= "", "codex is not on PATH and CODEX_PATH is unset")
    assert(vim.fn.executable(path) == 1, "Codex executable is not executable: " .. path)
  end)

  check("Codex adapters and model settings", function()
    assert(codex, "Codex module was not loaded")
    local options = codex.codecompanion_opts()
    assert(options.adapters and options.adapters.acp, "ACP adapters are missing")

    for _, name in ipairs({ "codex", "codex_ask", "codex_fix", "codex_research" }) do
      assert(type(options.adapters.acp[name]) == "function", "missing ACP adapter: " .. name)
      local adapter = options.adapters.acp[name]()
      assert(adapter ~= nil, "could not construct ACP adapter: " .. name)
      assert(
        adapter.defaults
          and adapter.defaults.session_config_options
          and adapter.defaults.session_config_options.model,
        "missing model defaults for " .. name
      )
      assert(
        adapter.defaults.session_config_options.thought_level,
        "missing reasoning level for " .. name
      )
    end

    for _, kind in ipairs({ "agent", "ask", "fix", "research" }) do
      local defaults = codex.model_defaults[kind]
      assert(defaults and defaults.model and defaults.reasoning_effort, "incomplete " .. kind .. " model defaults")
    end
  end)

  check("Chat buffer behavior", function()
    local options = codex.codecompanion_opts()
    local chat = options.interactions.chat
    assert(chat.adapter == "codex", "Codex is not the default chat adapter")
    assert(chat.opts.completion_provider == "default", "chat completion is not on-demand")
    assert(chat.keymaps.close == false, "chat close mapping was not disabled")
    assert(chat.keymaps.copilot_stats == false, "Copilot statistics mapping is still enabled")
    assert(options.display.chat.start_in_insert_mode == false, "chat starts in insert mode")
  end)

  if failures > 0 then
    vim.cmd("cquit 1")
  else
    vim.cmd("qa!")
  end
end, delay)
