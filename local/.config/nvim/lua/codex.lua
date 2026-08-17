local M = {}

local api = vim.api
local state = {
  agent_chat = nil,
  ask_chat = nil,
  research_chat = nil,
}

local function config_root()
  return vim.env.END4_NVIM_CONFIG or vim.fn.stdpath("config")
end

local function codex_acp_version()
  local version_file = config_root() .. "/codex-acp.version"
  if vim.fn.filereadable(version_file) == 1 then
    local version = vim.fn.readfile(version_file)[1]
    if version and version:match("^%d+%.%d+%.%d+$") then
      return version
    end
    error("invalid Codex ACP version in " .. version_file)
  end

  -- Keep an existing deployed configuration usable during the migration. New
  -- repository-owned configurations always carry codex-acp.version.
  return "1.4.0"
end

local function codex_path()
  local configured = vim.env.CODEX_PATH
  if configured and configured ~= "" then
    return configured
  end
  return vim.fn.exepath("codex")
end

local RESEARCH_SYSTEM_PROMPT = [[
You are Codex Research running inside Neovim.

This is a strictly read-only investigation session. Do not create, edit, delete,
format, or apply files. Do not run commands that mutate the repository. Inspect
the repository and its configuration as needed, and use live web search for
documentation or current external references when useful.

Return a concise, evidence-based research report in Markdown. Separate facts
from inferences. Include project references as `path:line` links when possible,
external sources as Markdown links, and a Sources section. When explaining a
flow or datapath, include a Mermaid diagram in a fenced `mermaid` block and a
short plain-text explanation below it. If web search is unavailable, say so
explicitly and do not present uncited current-web claims as facts.
]]

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Codex" })
end

local function valid_chat(chat)
  return chat and chat.bufnr and api.nvim_buf_is_valid(chat.bufnr)
end

local function project_root(bufnr)
  return vim.fs.root(bufnr or 0, { ".git", ".hg", ".svn" }) or vim.fn.getcwd()
end

local function relative_path(path, root)
  if not path or path == "" then
    return "[No file]"
  end
  local relative = vim.fs.relpath(root, path)
  return relative or path
end

local function diagnostics_for_line(bufnr, line)
  local diagnostics = vim.diagnostic.get(bufnr, { lnum = line - 1 })
  if #diagnostics == 0 then
    return "none"
  end

  local severity_names = {
    [vim.diagnostic.severity.ERROR] = "ERROR",
    [vim.diagnostic.severity.WARN] = "WARN",
    [vim.diagnostic.severity.INFO] = "INFO",
    [vim.diagnostic.severity.HINT] = "HINT",
  }
  local result = {}
  for _, diagnostic in ipairs(diagnostics) do
    table.insert(result, string.format("%s: %s", severity_names[diagnostic.severity] or "DIAGNOSTIC", diagnostic.message))
  end
  return table.concat(result, " | ")
end

local function selection_context(opts)
  opts = opts or {}
  local bufnr = api.nvim_get_current_buf()
  local root = project_root(bufnr)
  local path = api.nvim_buf_get_name(bufnr)
  local cursor = api.nvim_win_get_cursor(0)
  local cursor_line = math.max(1, cursor[1] or 1)
  local line1 = opts.line1 or cursor_line
  local line2 = opts.line2 or cursor_line
  local has_range = opts.range and opts.range > 0

  if has_range then
    line1 = math.max(1, math.min(line1, line2))
    line2 = math.max(line1, math.max(line1, line2))
  else
    line1 = cursor_line
    line2 = cursor_line
  end

  local lines = api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
  local content = table.concat(lines, "\n")
  local max_chars = 16000
  if #content > max_chars then
    content = content:sub(1, max_chars) .. "\n...[selection truncated]"
  end

  local filetype = vim.bo[bufnr].filetype
  local file = relative_path(path, root)
  local location = string.format("%s:%d-%d", file, line1, line2)

  return {
    bufnr = bufnr,
    root = root,
    path = path,
    file = file,
    filetype = filetype ~= "" and filetype or "text",
    line = cursor[1],
    line1 = line1,
    line2 = line2,
    location = location,
    content = content,
    diagnostics = diagnostics_for_line(bufnr, cursor[1]),
    has_range = has_range,
  }
end

local function context_block(context)
  local selection_title = context.has_range and "Marked code" or "Current line"
  return string.format(
    [[
Project root: `%s`
Current file: `%s`
Language: `%s`
Location: `%s`
Diagnostics on cursor line: `%s`

### %s
````%s { %s }
%s
````
]],
    context.root,
    context.file,
    context.filetype,
    context.location,
    context.diagnostics,
    selection_title,
    context.filetype,
    context.file,
    context.content
  )
end

local function scoped_prompt(instructions, context)
  return instructions .. "\n" .. context_block(context)
end

local function adapter(name, mode, formatted_name)
  return function()
    local adapter_opts = {
      name = name,
      formatted_name = formatted_name,
      commands = {
        default = {
          "npx",
          "--yes",
          "--package",
          "@agentclientprotocol/codex-acp@" .. codex_acp_version(),
          "codex-acp",
        },
      },
      defaults = {
        auth_method = "chat-gpt",
        mcpServers = {},
        timeout = 30000,
      },
      env = {
        CODEX_PATH = codex_path(),
        INITIAL_AGENT_MODE = mode,
        -- The preset declares this key for API-key users. Keep it empty when
        -- ChatGPT auth is selected instead of passing the preset's placeholder
        -- string to the ACP process.
        OPENAI_API_KEY = function()
          return os.getenv("OPENAI_API_KEY") or ""
        end,
      },
    }

    if mode == "read-only" then
      adapter_opts.env.CODEX_CONFIG = vim.json.encode({
        tools = {
          web_search = { mode = "live" },
        },
      })
      adapter_opts.parameters = {
        protocolVersion = 1,
        clientCapabilities = {
          fs = { readTextFile = true, writeTextFile = false },
        },
        clientInfo = {
          name = "Neovim Codex Research",
          version = "1.0.0",
        },
      }
    end

    return require("codecompanion.adapters").extend("codex", adapter_opts)
  end
end

function M.codecompanion_opts()
  return {
    adapters = {
      acp = {
        opts = {
          -- Only the configured Codex adapters should be offered. This also
          -- keeps unrelated providers, including Copilot, out of the picker.
          show_presets = false,
        },
        codex = adapter("codex", "agent", "Codex"),
        codex_research = adapter("codex_research", "read-only", "Codex Research"),
      },
      http = {
        opts = {
          show_presets = false,
        },
      },
    },
    interactions = {
      chat = {
        adapter = "codex",
      },
    },
    opts = {
      log_level = "WARN",
    },
  }
end

local function on_chat_wipe(chat)
  if not chat then
    return
  end
  api.nvim_create_autocmd("BufWipeout", {
    buffer = chat.bufnr,
    once = true,
    callback = function()
      if state.agent_chat == chat then
        state.agent_chat = nil
      end
      if state.ask_chat == chat then
        state.ask_chat = nil
      end
      if state.research_chat == chat then
        state.research_chat = nil
      end
    end,
  })
end

local function chat_window(layout)
  if layout == "float" then
    return { layout = "float", width = 0.78, height = 0.78 }
  end
  return { layout = "vertical", width = 0.42 }
end

-- ACP connections are initialized asynchronously by CodeCompanion. Submitting
-- from Chat.new's auto_submit path can race that initialization and create a
-- second connection. Wait for the established session before sending a
-- one-shot prompt.
local function submit_when_ready(chat)
  local attempts = 0
  local max_attempts = 300

  local function try_submit()
    if not valid_chat(chat) or chat.current_request then
      return
    end

    local connection = chat.acp_connection
    if connection and connection:is_connected() then
      chat:submit({ auto_submit = true })
      return
    end

    attempts = attempts + 1
    if attempts >= max_attempts then
      notify("Codex ACP did not finish initializing; the request was not sent.", vim.log.levels.ERROR)
      return
    end
    vim.defer_fn(try_submit, 100)
  end

  vim.defer_fn(try_submit, 0)
end

local function open_agent_chat()
  local codecompanion = require("codecompanion")
  if valid_chat(state.agent_chat) then
    state.agent_chat.ui:open()
    return state.agent_chat
  end

  state.agent_chat = codecompanion.chat({
    params = { adapter = "codex" },
    title = "Codex Chat",
    window_opts = chat_window("vertical"),
    stop_context_insertion = true,
  })
  on_chat_wipe(state.agent_chat)
  return state.agent_chat
end

local function open_one_shot(prompt, title)
  local codecompanion = require("codecompanion")
  local chat = codecompanion.chat({
    params = { adapter = "codex_research" },
    title = title,
    user_prompt = prompt,
    auto_submit = false,
    window_opts = chat_window("float"),
    stop_context_insertion = true,
    callbacks = {
      on_created = function(created)
        created:set_system_prompt(RESEARCH_SYSTEM_PROMPT)
      end,
    },
  })
  on_chat_wipe(chat)
  if chat then
    submit_when_ready(chat)
  end
  return chat
end

function M.ask(opts)
  opts = opts or {}
  local context = selection_context(opts)
  local function continue_with_question(question)
    if not question or vim.trim(question) == "" then
      return
    end

    local prompt = scoped_prompt(
      [[Answer this question about the supplied Neovim context. This is read-only: do not edit files or run mutating commands. Explain the relevant behavior clearly, cite repository locations as `path:line`, and distinguish what is directly observed from what is inferred.]],
      context
    ) .. "\nQuestion: " .. vim.trim(question)
    state.ask_chat = open_one_shot(prompt, "Codex Ask")
  end

  local question = vim.trim(opts.args or "")
  if question ~= "" then
    continue_with_question(question)
  else
    vim.ui.input({ prompt = "Codex ask: " }, continue_with_question)
  end
end

function M.fix(opts)
  opts = opts or {}
  local context = selection_context(opts)
  local function continue_with_request(request)
    if not request or vim.trim(request) == "" then
      return
    end

    local prompt = scoped_prompt(
      [[Act as a careful project-scoped coding agent. Implement the requested quick fix using the supplied context. Stay inside the project root. Inspect related files before editing, explain the intended change, and use the normal Codex/CodeCompanion approval and diff flow. Never silently discard or overwrite unrelated user changes.]],
      context
    ) .. "\nRequested fix: " .. vim.trim(request)

    local codecompanion = require("codecompanion")
    state.agent_chat = codecompanion.chat({
      params = { adapter = "codex" },
      title = "Codex Quick Fix",
      user_prompt = prompt,
      auto_submit = false,
      window_opts = chat_window("vertical"),
      stop_context_insertion = true,
    })
    on_chat_wipe(state.agent_chat)
    submit_when_ready(state.agent_chat)
  end

  local request = vim.trim(opts.args or "")
  if request ~= "" then
    continue_with_request(request)
  else
    vim.ui.input({ prompt = "Codex quick fix: " }, continue_with_request)
  end
end

local function research_prompt(scope, question)
  local scope_instruction = {
    repo = "Prioritize repository files, local documentation, references, symbols, and call/data paths. Do not use the web unless it is required to clarify a local dependency.",
    web = "Prioritize live web research from primary documentation and authoritative references. Relate external findings back to the repository when possible.",
    mixed = "Combine repository inspection with live web research when that improves the answer. Cite both local files and external sources.",
  }

  return string.format(
    [[Research scope: %s
%s

Research request: %s]],
    scope,
    scope_instruction[scope] or scope_instruction.mixed,
    question or "Open the research workspace and wait for my first question."
  )
end

local function new_research_chat(prompt, previous)
  local codecompanion = require("codecompanion")
  local messages
  local session_id

  if valid_chat(previous) then
    messages = vim.deepcopy(previous.messages)
    session_id = previous.acp_connection and previous.acp_connection.session_id or nil
    if previous.current_request then
      notify("The current research request is still running.", vim.log.levels.WARN)
      previous.ui:open()
      return previous
    end
    previous:close()
  end

  local chat = codecompanion.chat({
    params = { adapter = "codex_research" },
    acp_session_id = session_id,
    messages = messages,
    title = "Codex Research",
    user_prompt = prompt,
    auto_submit = false,
    window_opts = chat_window("vertical"),
    stop_context_insertion = true,
    callbacks = {
      on_created = function(created)
        created:set_system_prompt(RESEARCH_SYSTEM_PROMPT)
      end,
    },
  })
  on_chat_wipe(chat)
  if prompt then
    submit_when_ready(chat)
  end
  return chat
end

function M.research(args)
  args = args or {}
  local raw = vim.trim(args.args or "")
  local words = raw == "" and {} or vim.split(raw, "%s+", { trimempty = true })
  local scope = "mixed"
  if words[1] == "repo" or words[1] == "web" or words[1] == "mixed" then
    scope = table.remove(words, 1)
  end
  local question = vim.trim(table.concat(words, " "))
  local prompt = question ~= "" and research_prompt(scope, question) or nil

  if not prompt and valid_chat(state.research_chat) then
    state.research_chat.ui:open()
    return
  end

  state.research_chat = new_research_chat(prompt, state.research_chat)
end

function M.research_preview()
  if vim.fn.exists(":MarkdownPreviewToggle") ~= 2 then
    notify("Markdown preview is not available yet; run :Lazy load markdown-preview.nvim first.", vim.log.levels.WARN)
    return
  end
  vim.cmd("MarkdownPreviewToggle")
end

function M.research_stop()
  if valid_chat(state.research_chat) then
    state.research_chat:close()
    state.research_chat = nil
  end
end

local function create_commands()
  api.nvim_create_user_command("CodexChat", function()
    open_agent_chat()
  end, { desc = "Open the Codex agent chat" })

  api.nvim_create_user_command("CodexAsk", function(args)
    M.ask(args)
  end, { nargs = "*", range = true, desc = "Ask Codex about the current code" })

  api.nvim_create_user_command("CodexFix", function(args)
    M.fix(args)
  end, { nargs = "*", range = true, desc = "Run a reviewed Codex quick fix" })

  api.nvim_create_user_command("CodexResearch", function(args)
    M.research(args)
  end, { nargs = "*", desc = "Open or query the read-only Codex research workspace" })

  api.nvim_create_user_command("CodexResearchPreview", function()
    M.research_preview()
  end, { desc = "Preview the research report with Mermaid rendering" })

  api.nvim_create_user_command("CodexResearchStop", function()
    M.research_stop()
  end, { desc = "Close the Codex research workspace" })

  api.nvim_create_user_command("CodexChanges", function()
    require("codecompanion").changes()
  end, { desc = "List files changed by the current Codex chat" })
end

local function create_keymaps()
  local opts = { noremap = true, silent = true }
  vim.keymap.set("n", "<leader>cc", "<cmd>CodexChat<cr>", vim.tbl_extend("force", opts, { desc = "Codex Chat" }))
  vim.keymap.set("n", "<leader>ca", function()
    M.ask({})
  end, vim.tbl_extend("force", opts, { desc = "Codex Ask" }))
  vim.keymap.set("n", "<leader>cf", function()
    M.fix({})
  end, vim.tbl_extend("force", opts, { desc = "Codex Quick Fix" }))
  vim.keymap.set("n", "<leader>cr", "<cmd>CodexResearch<cr>", vim.tbl_extend("force", opts, { desc = "Codex Research" }))
  vim.keymap.set("n", "<leader>cR", "<cmd>CodexResearchPreview<cr>", vim.tbl_extend("force", opts, { desc = "Preview Codex Research" }))
  vim.keymap.set("v", "<leader>ca", ":CodexAsk<CR>", vim.tbl_extend("force", opts, { desc = "Codex Ask Selection" }))
  vim.keymap.set("v", "<leader>cf", ":CodexFix<CR>", vim.tbl_extend("force", opts, { desc = "Codex Fix Selection" }))
end

local function configure_chat_ui()
  local group = api.nvim_create_augroup("codex_ui", { clear = true })
  api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "codecompanion",
    callback = function(event)
      vim.opt_local.wrap = true
      vim.opt_local.linebreak = true
      vim.opt_local.conceallevel = 2
      vim.keymap.set("n", "<leader>cR", "<cmd>CodexResearchPreview<cr>", {
        buffer = event.buf,
        desc = "Preview Codex Research with Mermaid",
        silent = true,
      })
    end,
  })
end

function M.setup()
  create_commands()
  create_keymaps()
  configure_chat_ui()
end

return M
