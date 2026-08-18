local M = {}

local api = vim.api

local DEFAULT_MODEL_DEFAULTS = {
  agent = { model = "gpt-5.6-luna", reasoning_effort = "max" },
  ask = { model = "gpt-5.6-luna", reasoning_effort = "high" },
  fix = { model = "gpt-5.6-luna", reasoning_effort = "high" },
  research = { model = "gpt-5.6-luna", reasoning_effort = "max" },
}

local state = {
  initialized = false,
  history = nil,
  records = {},
  by_buf = {},
  last_by_kind = {},
}

local function copy(value)
  return vim.deepcopy(value)
end

local function merge_model_defaults()
  local configured = vim.g.codex_model_defaults
  if type(configured) ~= "table" then
    return copy(DEFAULT_MODEL_DEFAULTS)
  end
  return vim.tbl_deep_extend("force", copy(DEFAULT_MODEL_DEFAULTS), configured)
end

M.model_defaults = merge_model_defaults()

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Codex" })
end

local function valid_chat(chat)
  return chat
    and chat.bufnr
    and api.nvim_buf_is_valid(chat.bufnr)
    and chat.ui
end

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
  return "1.4.0"
end

local function codex_path()
  local configured = vim.env.CODEX_PATH
  if configured and configured ~= "" then
    return configured
  end
  return vim.fn.exepath("codex")
end

local function project_root(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()
  return vim.fs.root(bufnr, { ".git", ".hg", ".svn" }) or vim.fn.getcwd()
end

local function relative_path(path, root)
  if not path or path == "" then
    return "[No file]"
  end
  return vim.fs.relpath(root, path) or path
end

local function diagnostics_for_line(bufnr, line)
  local diagnostics = vim.diagnostic.get(bufnr, { lnum = math.max(1, line or 1) - 1 })
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
    table.insert(
      result,
      string.format(
        "%s: %s",
        severity_names[diagnostic.severity] or "DIAGNOSTIC",
        diagnostic.message
      )
    )
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
    line2 = math.max(line1, line2)
  else
    line1 = cursor_line
    line2 = cursor_line
  end

  local lines = api.nvim_buf_get_lines(bufnr, line1 - 1, line2, false)
  local content = table.concat(lines, "\n")
  if #content > 16000 then
    content = content:sub(1, 16000) .. "\n...[selection truncated]"
  end

  local filetype = vim.bo[bufnr].filetype
  local file = relative_path(path, root)
  return {
    bufnr = bufnr,
    root = root,
    path = path,
    file = file,
    filetype = filetype ~= "" and filetype or "text",
    line = cursor_line,
    line1 = line1,
    line2 = line2,
    location = string.format("%s:%d-%d", file, line1, line2),
    content = content,
    diagnostics = diagnostics_for_line(bufnr, cursor_line),
    has_range = has_range,
  }
end

local function context_block(context)
  local fence = string.rep(string.char(96), 4)
  local selection_title = context.has_range and "Marked code" or "Current line"
  return string.format(
    [[
Project root: %s
Current file: %s
Language: %s
Location: %s
Diagnostics on cursor line: %s

### %s
%s%s { %s }
%s
%s
]],
    context.root,
    context.file,
    context.filetype,
    context.location,
    context.diagnostics,
    selection_title,
    fence,
    context.filetype,
    context.file,
    context.content,
    fence
  )
end

local function scoped_prompt(instructions, context)
  return instructions .. "\n" .. context_block(context)
end

local RESEARCH_SYSTEM_PROMPT = [[
You are Codex Research running inside Neovim.

This is a strictly read-only investigation session. Do not create, edit,
delete, format, or apply files. Do not run commands that mutate the repository.
Inspect repository files and configuration as needed. Use live web search for
documentation or current external references when useful.

Return a concise, evidence-based research report in Markdown. Separate facts
from inferences. Include project references as path:line links when possible,
external sources as Markdown links, and a Sources section. When explaining a
flow or datapath, include a Mermaid diagram in a fenced mermaid block and a
short plain-text explanation below it. If web search is unavailable, say so
explicitly and do not present uncited current-web claims as facts.
]]

local function model_for(kind)
  local defaults = M.model_defaults[kind] or DEFAULT_MODEL_DEFAULTS.agent
  local effort = defaults.reasoning_effort or defaults.thought_level or "high"
  return {
    model = defaults.model,
    reasoning_effort = effort,
    thought_level = effort,
  }
end

local function adapter(name, kind, mode, formatted_name)
  return function()
    local model = model_for(kind)
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
        auth_method = vim.g.codex_auth_method or "chat-gpt",
        mcpServers = {},
        timeout = 30000,
        session_config_options = {
          model = model.model,
          thought_level = model.thought_level,
        },
      },
      env = {
        CODEX_PATH = codex_path(),
        INITIAL_AGENT_MODE = mode,
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
          fs = {
            readTextFile = true,
            writeTextFile = false,
          },
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
          show_presets = false,
        },
        codex = adapter("codex", "agent", "agent", "Codex"),
        codex_ask = adapter("codex_ask", "ask", "read-only", "Codex Ask"),
        codex_fix = adapter("codex_fix", "fix", "agent", "Codex Quick Fix"),
        codex_research = adapter("codex_research", "research", "read-only", "Codex Research"),
      },
      http = {
        opts = {
          show_presets = false,
        },
      },
    },
    interactions = {
      background = {
        opts = {
          enabled = false,
        },
      },
      chat = {
        adapter = "codex",
        keymaps = {
          close = false,
          copilot_stats = false,
        },
        opts = {
          completion_provider = "default",
        },
      },
    },
    display = {
      chat = {
        start_in_insert_mode = false,
        window = {
          layout = "vertical",
          width = 0.42,
          position = "right",
        },
      },
    },
    opts = {
      log_level = "WARN",
    },
  }
end

local function history_path()
  return vim.fn.stdpath("state") .. "/codex/sessions.json"
end

local function ensure_history()
  if state.history ~= nil then
    return state.history
  end

  state.history = {}
  local path = history_path()
  if vim.fn.filereadable(path) == 1 then
    local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), "\n"))
    if ok and type(decoded) == "table" then
      state.history = decoded.sessions or decoded
    end
  end
  if type(state.history) ~= "table" then
    state.history = {}
  end
  return state.history
end

local function persisted_messages(messages)
  local result = {}
  for _, message in ipairs(messages or {}) do
    local item = {
      role = message.role,
      content = type(message.content) == "string" and message.content or nil,
    }
    if type(message.reasoning) == "string" then
      item.reasoning = message.reasoning
    end
    if message.tools then
      item.tools = copy(message.tools)
    end
    if message._meta then
      item._meta = copy(message._meta)
    end
    table.insert(result, item)
  end

  local ok = pcall(vim.json.encode, result)
  if ok then
    return result
  end

  local minimal = {}
  for _, message in ipairs(result) do
    table.insert(minimal, {
      role = message.role,
      content = message.content,
      reasoning = message.reasoning,
    })
  end
  return minimal
end

local function record_key(record)
  if record.session_id and record.session_id ~= "" then
    return "session:" .. record.session_id
  end
  return "local:" .. tostring(record.local_id)
end

local function write_history()
  ensure_history()
  local path = history_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local payload = {
    version = 1,
    sessions = state.history,
  }
  local ok, encoded = pcall(vim.json.encode, payload)
  if ok then
    vim.fn.writefile({ encoded }, path)
  end
end

local function upsert_history(record)
  ensure_history()
  local key = record_key(record)
  local serial = {}
  for name, value in pairs(record) do
    if name ~= "chat" then
      serial[name] = copy(value)
    end
  end
  local found

  for index, existing in ipairs(state.history) do
    if record_key(existing) == key then
      state.history[index] = serial
      found = true
      break
    end
  end
  if not found then
    table.insert(state.history, serial)
  end

  table.sort(state.history, function(left, right)
    return (left.updated_at or left.created_at or 0) > (right.updated_at or right.created_at or 0)
  end)
  while #state.history > 200 do
    table.remove(state.history)
  end
  write_history()
end

local function update_record(chat, status)
  local record = chat and chat.codex_record
  if not record then
    return
  end

  local connection = chat.acp_connection
  if connection and connection.session_id then
    record.session_id = connection.session_id
  end
  record.title = chat.title or record.title
  record.status = status or record.status or "open"
  record.updated_at = os.time()
  record.messages = persisted_messages(chat.messages)
  upsert_history(record)
end

local function attach_chat(chat, kind, opts)
  opts = opts or {}
  ensure_history()

  local now = os.time()
  local record = {
    local_id = tostring(chat.id),
    session_id = opts.session_id,
    kind = kind,
    adapter = chat.adapter and chat.adapter.name,
    title = chat.title or ("Codex " .. kind),
    project_root = opts.project_root or project_root(opts.bufnr),
    cwd = vim.fn.getcwd(),
    status = "open",
    created_at = now,
    updated_at = now,
    chat = chat,
  }

  chat.codex_record = record
  state.records[chat.id] = record
  state.by_buf[chat.bufnr] = chat
  state.last_by_kind[kind] = record

  chat:add_callback("on_ready", function(current)
    update_record(current, "ready")
  end)
  chat:add_callback("on_checkpoint", function(current)
    update_record(current, current.current_request and "running" or "open")
  end)
  chat:add_callback("on_submitted", function(current)
    update_record(current, "running")
  end)
  chat:add_callback("on_completed", function(current)
    update_record(current, "completed")
  end)
  chat:add_callback("on_cancelled", function(current)
    update_record(current, "interrupted")
  end)
  chat:add_callback("on_closed", function(current)
    update_record(current, "closed")
  end)

  api.nvim_create_autocmd("BufWipeout", {
    group = api.nvim_create_augroup("codex_session_" .. chat.bufnr, { clear = true }),
    buffer = chat.bufnr,
    once = true,
    callback = function()
      update_record(chat, chat.current_request and "interrupted" or "closed")
      state.by_buf[chat.bufnr] = nil
      record.chat = nil
    end,
  })

  update_record(chat, "open")
  return record
end

local function chat_for_buffer(bufnr)
  local chat = state.by_buf[bufnr]
  if valid_chat(chat) then
    return chat
  end
  return nil
end

local function chat_window()
  return {
    layout = "vertical",
    width = 0.42,
    position = "right",
  }
end

local function resolve_adapter(name)
  local config = require("codecompanion.config")
  local adapters = require("codecompanion.adapters")
  local configured = config.adapters.acp[name]
  if not configured then
    return nil
  end
  return adapters.resolve(configured)
end

local function buffer_context(bufnr, opts)
  return require("codecompanion.utils.context").get(bufnr or api.nvim_get_current_buf(), opts or {})
end

local function wait_for_chat(chat, predicate, callback, max_attempts)
  local attempts = 0
  max_attempts = max_attempts or 200

  local function try()
    if not valid_chat(chat) then
      callback(false)
      return
    end
    local ok, ready = pcall(predicate)
    if ok and ready then
      callback(true)
      return
    end
    attempts = attempts + 1
    if attempts >= max_attempts then
      callback(false)
      return
    end
    vim.defer_fn(try, 100)
  end

  try()
end

local function submit_when_ready(chat)
  wait_for_chat(chat, function()
    return chat.acp_connection and chat.acp_connection:is_connected()
  end, function(ready)
    if not ready then
      notify("Codex ACP did not finish initializing; the request was not sent.", vim.log.levels.ERROR)
      return
    end
    if valid_chat(chat) and not chat.current_request then
      chat:submit({ auto_submit = true })
    end
  end, 300)
end

local function restore_session_when_ready(chat, record)
  if not record.session_id then
    return
  end

  wait_for_chat(chat, function()
    return chat.acp_connection and chat.acp_connection:is_ready()
  end, function(ready)
    if not ready then
      notify("Codex session could not be connected; saved chat text remains available.", vim.log.levels.WARN)
      update_record(chat, "disconnected")
      return
    end

    local updates = {}
    local ok, loaded = pcall(function()
      return chat.acp_connection:load_session(record.session_id, {
        on_session_update = function(update)
          table.insert(updates, update)
        end,
      })
    end)

    if not ok or not loaded then
      notify("Codex could not load that session; saved chat text remains available.", vim.log.levels.WARN)
      update_record(chat, "unavailable")
      return
    end

    require("codecompanion.interactions.chat.acp.commands").link_buffer_to_session(
      chat.bufnr,
      chat.acp_connection.session_id
    )
    require("codecompanion.interactions.chat.acp.render").restore_session(chat, updates)
    if record.title and record.title ~= "" then
      chat:set_title(record.title)
    end
    update_record(chat, "ready")
    notify("Resumed Codex session: " .. (record.title or record.session_id))
  end, 300)
end

local function new_chat(kind, opts)
  opts = opts or {}
  local adapter_name = ({
    agent = "codex",
    ask = "codex_ask",
    fix = "codex_fix",
    research = "codex_research",
  })[kind]
  local adapter_instance = resolve_adapter(adapter_name)
  if not adapter_instance then
    notify("Codex adapter is unavailable: " .. tostring(adapter_name), vim.log.levels.ERROR)
    return nil
  end

  local messages = copy(opts.messages or {})
  if opts.prompt and opts.prompt ~= "" then
    table.insert(messages, {
      role = "user",
      content = opts.prompt,
    })
  end

  local chat = require("codecompanion.interactions.chat").new({
    adapter = adapter_instance,
    buffer_context = buffer_context(opts.bufnr, opts.context_opts),
    messages = #messages > 0 and messages or nil,
    title = opts.title or ("Codex " .. kind),
    auto_submit = false,
    hidden = opts.hidden or false,
    stop_context_insertion = true,
    tools = opts.tools,
    window_opts = opts.window_opts or chat_window(),
  })
  if not chat then
    notify("CodeCompanion could not create the Codex chat.", vim.log.levels.ERROR)
    return nil
  end

  -- CodeCompanion starts ACP initialization on the next scheduled tick. Seed
  -- restored chats before that tick so its handler uses the requested session
  -- instead of creating a new one.
  if opts.session_id then
    chat.acp_connection = require("codecompanion.acp").new({
      adapter = chat.adapter,
      chat = chat,
      session_id = opts.session_id,
    })
  end

  if kind == "research" then
    chat:set_system_prompt(RESEARCH_SYSTEM_PROMPT)
  end

  local record
  if opts.register ~= false then
    record = attach_chat(chat, kind, {
      bufnr = opts.bufnr,
      project_root = opts.project_root,
      session_id = opts.session_id,
    })
  end

  if opts.session_id and record then
    restore_session_when_ready(chat, record)
  elseif opts.submit and #messages > 0 then
    submit_when_ready(chat)
  end

  return chat
end

local function research_prompt(scope, question)
  local instructions = {
    repo = "Prioritize repository files, local documentation, references, symbols, and call/data paths. Do not use the web unless required to clarify a local dependency.",
    web = "Prioritize live web research from primary documentation and authoritative references. Relate external findings back to the repository when possible.",
    mixed = "Combine repository inspection with live web research when that improves the answer. Cite both local files and external sources.",
  }
  return string.format(
    "Research scope: %s\n%s\n\nResearch request: %s",
    scope,
    instructions[scope] or instructions.mixed,
    question or "Open the research workspace and wait for my first question."
  )
end

function M.ask(opts)
  opts = opts or {}
  local context = selection_context(opts)

  local function ask_question(question)
    question = question and vim.trim(question) or ""
    if question == "" then
      return
    end
    local prompt = scoped_prompt(
      "Answer this question about the supplied Neovim context. This is read-only: do not edit files or run mutating commands. Explain the behavior clearly, cite repository locations as path:line, and distinguish observations from inferences.",
      context
    ) .. "\nQuestion: " .. question
    new_chat("ask", {
      bufnr = context.bufnr,
      title = "Codex Ask: " .. context.location,
      prompt = prompt,
      submit = true,
    })
  end

  local question = vim.trim(opts.args or "")
  if question ~= "" then
    ask_question(question)
  else
    vim.ui.input({ prompt = "Codex ask: " }, ask_question)
  end
end

function M.fix(opts)
  opts = opts or {}
  local context = selection_context(opts)

  local function request_fix(request)
    request = request and vim.trim(request) or ""
    if request == "" then
      return
    end
    local prompt = scoped_prompt(
      "Act as a careful project-scoped coding agent. Implement the requested quick fix using the supplied context. Stay inside the project root, inspect related files before editing, explain the intended change, and use the normal CodeCompanion approval and diff flow. Never silently discard or overwrite unrelated user changes.",
      context
    ) .. "\nRequested fix: " .. request
    new_chat("fix", {
      bufnr = context.bufnr,
      title = "Codex Quick Fix: " .. context.location,
      prompt = prompt,
      submit = true,
    })
  end

  local request = vim.trim(opts.args or "")
  if request ~= "" then
    request_fix(request)
  else
    vim.ui.input({ prompt = "Codex quick fix: " }, request_fix)
  end
end

function M.chat_new()
  return new_chat("agent", {
    title = "Codex Chat",
  })
end

function M.chat()
  local record = state.last_by_kind.agent
  if record and valid_chat(record.chat) then
    record.chat.ui:open()
    return record.chat
  end
  return M.chat_new()
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

  if question == "" then
    local last = state.last_by_kind.research
    if last and valid_chat(last.chat) then
      last.chat.ui:open()
      return last.chat
    end
  end

  return new_chat("research", {
    title = "Codex Research",
    prompt = question ~= "" and research_prompt(scope, question) or nil,
    submit = question ~= "",
  })
end

function M.research_new()
  return new_chat("research", {
    title = "Codex Research",
  })
end

function M.research_preview()
  local record = state.last_by_kind.research
  if not record or not valid_chat(record.chat) then
    notify("Open a Codex research session before previewing it.", vim.log.levels.WARN)
    return
  end

  record.chat.ui:open()
  vim.schedule(function()
    if vim.fn.exists(":MarkdownPreviewToggle") ~= 2 then
      notify("Markdown preview is unavailable; load markdown-preview.nvim first.", vim.log.levels.WARN)
      return
    end
    vim.cmd("MarkdownPreviewToggle")
  end)
end

function M.research_stop()
  local record = state.last_by_kind.research
  if record and valid_chat(record.chat) then
    record.chat:stop()
    record.chat.ui:hide()
    update_record(record.chat, "interrupted")
  end
end

local function parse_iso_time(value)
  if type(value) ~= "string" then
    return 0
  end
  local year, month, day, hour, minute, second = value:match(
    "^(%d%d%d%d)-(%d%d)-(%d%d)[T ](%d%d):(%d%d):(%d%d)"
  )
  if not year then
    return 0
  end
  return os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(minute),
    sec = tonumber(second),
  })
end

local function current_project()
  return project_root(api.nvim_get_current_buf())
end

local function collect_local_entries()
  ensure_history()
  local entries = {}
  local seen = {}
  local function add(record)
    local key = record_key(record)
    if seen[key] then
      return
    end
    seen[key] = true
    table.insert(entries, {
      record = record,
      kind = record.kind or "agent",
      title = record.title or record.session_id or "Codex session",
      session_id = record.session_id,
      project_root = record.project_root,
      updated_at = record.updated_at or record.created_at or 0,
      source = "local",
    })
  end

  for _, record in pairs(state.records) do
    add(record)
  end
  for _, record in ipairs(state.history) do
    add(record)
  end
  return entries, seen
end

local function list_from_connection(connection)
  if not connection or not connection:is_ready() or not connection:can_list_sessions() then
    return {}
  end
  local ok, sessions = pcall(connection.session_list, connection, { max_sessions = 500 })
  if not ok or type(sessions) ~= "table" then
    return {}
  end
  return sessions
end

local function create_session_browser(callback)
  for _, record in pairs(state.records) do
    if valid_chat(record.chat) then
      local connection = record.chat.acp_connection
      if connection and connection:is_ready() and connection:can_list_sessions() then
        callback(list_from_connection(connection))
        return
      end
    end
  end

  local browser = new_chat("agent", {
    title = "Codex Session Browser",
    hidden = true,
    register = false,
    tools = "none",
  })
  if not browser then
    callback({})
    return
  end

  state.browser = browser
  wait_for_chat(browser, function()
    return browser.acp_connection and browser.acp_connection:is_ready()
  end, function(ready)
    local sessions = {}
    if ready then
      sessions = list_from_connection(browser.acp_connection)
    end
    if valid_chat(browser) then
      browser:close()
    end
    state.browser = nil
    callback(sessions)
  end, 150)
end

local function picker_label(entry)
  local kind = entry.kind or "agent"
  local title = entry.title or entry.session_id or "Codex session"
  local project = entry.project_root and vim.fn.fnamemodify(entry.project_root, ":t") or "current project"
  local status = entry.record and entry.record.status or entry.source or "saved"
  return string.format(
    "[%s/%s] %s — %s — %s",
    kind,
    status,
    title,
    project,
    os.date("%Y-%m-%d %H:%M", entry.updated_at or 0)
  )
end

local function restore_picker_entry(entry)
  local record = entry.record or {
    kind = entry.kind or "agent",
    title = entry.title,
    session_id = entry.session_id,
    project_root = entry.project_root,
    updated_at = entry.updated_at,
  }
  if valid_chat(record.chat) then
    record.chat.ui:open()
    return record.chat
  end

  local kind = record.kind
  if kind ~= "agent" and kind ~= "ask" and kind ~= "fix" and kind ~= "research" then
    kind = "agent"
  end
  return new_chat(kind, {
    title = record.title,
    messages = record.messages,
    session_id = record.session_id,
    project_root = record.project_root,
  })
end

function M.sessions()
  local entries, seen = collect_local_entries()
  create_session_browser(function(native_sessions)
    for _, session in ipairs(native_sessions) do
      local session_id = session.sessionId
      if session_id and not seen["session:" .. session_id] then
        table.insert(entries, {
          kind = (session.title and session.title:lower():find("research", 1, true)) and "research" or "agent",
          title = session.title or session_id,
          session_id = session_id,
          project_root = session.cwd or current_project(),
          updated_at = parse_iso_time(session.updatedAt),
          source = "acp",
        })
        seen["session:" .. session_id] = true
      end
    end

    if #entries == 0 then
      notify("No Codex sessions were found.", vim.log.levels.INFO)
      return
    end

    local root = current_project()
    table.sort(entries, function(left, right)
      local left_current = left.project_root == root and 1 or 0
      local right_current = right.project_root == root and 1 or 0
      if left_current ~= right_current then
        return left_current > right_current
      end
      return (left.updated_at or 0) > (right.updated_at or 0)
    end)

    local labels = vim.tbl_map(picker_label, entries)
    vim.ui.select(labels, { prompt = "Codex sessions" }, function(_, index)
      if index then
        restore_picker_entry(entries[index])
      end
    end)
  end)
end

M.session_picker = M.sessions

function M.hide()
  local current = chat_for_buffer(api.nvim_get_current_buf())
  if current then
    current.ui:hide()
    return
  end
  for _, record in pairs(state.records) do
    if valid_chat(record.chat) and record.chat.ui:is_visible() then
      record.chat.ui:hide()
      return
    end
  end
end

local function define_command(name, callback, opts)
  pcall(api.nvim_del_user_command, name)
  api.nvim_create_user_command(name, callback, opts or {})
end

local function create_commands()
  define_command("CodexChat", function()
    M.chat()
  end, { desc = "Open or resume Codex agent chat" })
  define_command("CodexChatNew", function()
    M.chat_new()
  end, { desc = "Create a new Codex agent chat" })
  define_command("CodexAsk", function(args)
    M.ask(args)
  end, { nargs = "*", range = true, desc = "Ask Codex about the current code" })
  define_command("CodexFix", function(args)
    M.fix(args)
  end, { nargs = "*", range = true, desc = "Run a reviewed Codex quick fix" })
  define_command("CodexResearch", function(args)
    M.research(args)
  end, { nargs = "*", desc = "Open or query read-only Codex research" })
  define_command("CodexResearchNew", function()
    M.research_new()
  end, { desc = "Create a new Codex research session" })
  define_command("CodexResearchPreview", function()
    M.research_preview()
  end, { desc = "Preview Codex research with Mermaid rendering" })
  define_command("CodexResearchStop", function()
    M.research_stop()
  end, { desc = "Stop and hide the current Codex research session" })
  define_command("CodexSessions", function()
    M.sessions()
  end, { desc = "Pick an active or saved Codex session" })
  define_command("CodexSessionPicker", function()
    M.sessions()
  end, { desc = "Pick an active or saved Codex session" })
  define_command("CodexHide", function()
    M.hide()
  end, { desc = "Hide the current Codex chat" })
  define_command("CodexChanges", function()
    require("codecompanion").changes()
  end, { desc = "List files changed by the current Codex chat" })
end

local function remove_stale_mapping(lhs)
  local mapping = vim.fn.maparg(lhs, "n", false, true)
  if type(mapping) == "table" and mapping.desc == "Preview Codex Research" then
    pcall(vim.keymap.del, "n", lhs)
  end
end

local function create_keymaps()
  local opts = { noremap = true, silent = true }
  remove_stale_mapping("<leader>zR")
  vim.keymap.set("n", "<leader>zc", "<cmd>CodexChat<cr>", vim.tbl_extend("force", opts, {
    desc = "Codex Chat",
  }))
  vim.keymap.set("n", "<leader>zC", "<cmd>CodexChatNew<cr>", vim.tbl_extend("force", opts, {
    desc = "New Codex Chat",
  }))
  vim.keymap.set("n", "<leader>za", function()
    M.ask({})
  end, vim.tbl_extend("force", opts, { desc = "Codex Ask" }))
  vim.keymap.set("n", "<leader>zf", function()
    M.fix({})
  end, vim.tbl_extend("force", opts, { desc = "Codex Quick Fix" }))
  vim.keymap.set("n", "<leader>zs", "<cmd>CodexResearch<cr>", vim.tbl_extend("force", opts, {
    desc = "Codex Research",
  }))
  vim.keymap.set("n", "<leader>zS", "<cmd>CodexResearchPreview<cr>", vim.tbl_extend("force", opts, {
    desc = "Preview Codex Research",
  }))
  vim.keymap.set("n", "<leader>zr", "<cmd>CodexSessions<cr>", vim.tbl_extend("force", opts, {
    desc = "Codex Session Picker",
  }))
  vim.keymap.set("v", "<leader>za", ":CodexAsk<CR>", vim.tbl_extend("force", opts, {
    desc = "Codex Ask Selection",
  }))
  vim.keymap.set("v", "<leader>zf", ":CodexFix<CR>", vim.tbl_extend("force", opts, {
    desc = "Codex Fix Selection",
  }))
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

      local function hide()
        local chat = chat_for_buffer(event.buf)
        if chat then
          vim.cmd("stopinsert")
          chat.ui:hide()
        end
      end

      vim.keymap.set("n", "<C-c>", hide, {
        buffer = event.buf,
        desc = "Hide Codex chat",
        silent = true,
      })
      vim.keymap.set("i", "<C-c>", hide, {
        buffer = event.buf,
        desc = "Hide Codex chat",
        silent = true,
      })
      vim.keymap.set("n", "<leader>zS", "<cmd>CodexResearchPreview<cr>", {
        buffer = event.buf,
        desc = "Preview Codex Research with Mermaid",
        silent = true,
      })
    end,
  })
end

local function configure_lifecycle()
  local group = api.nvim_create_augroup("codex_lifecycle", { clear = true })
  api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      for _, record in pairs(state.records) do
        local chat = record.chat
        if valid_chat(chat) then
          local was_running = chat.current_request ~= nil
          if was_running then
            pcall(chat.stop, chat)
          end
          update_record(chat, was_running and "interrupted" or record.status)
        end
      end
      write_history()
    end,
  })
end

function M.setup()
  if state.initialized then
    return
  end
  state.initialized = true
  ensure_history()
  create_commands()
  create_keymaps()
  configure_chat_ui()
  configure_lifecycle()
end

return M
