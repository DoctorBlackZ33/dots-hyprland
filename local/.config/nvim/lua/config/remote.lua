local M = {}

local uv = vim.uv or vim.loop
local ssh_config_paths = {
  vim.fn.expand("~/.ssh/config"),
}

local state = {
  setup = false,
  phase = "disconnected",
  target = "local",
  token = 0,
  host = nil,
  mount_dir = nil,
  job_id = nil,
  system_handles = {},
  output = {},
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "IDE remote" })
end

local function normalize(path)
  local value = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  if value ~= "/" then
    value = value:gsub("/+$", "")
  end
  return value
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

M.shell_quote = shell_quote

local function schedule_after(delay, callback)
  local timer = uv.new_timer()
  timer:start(delay, 0, function()
    timer:stop()
    timer:close()
    vim.schedule(callback)
  end)
end

---@param command string[]
---@param opts? table
---@param timeout? number
---@param callback fun(result: table, timed_out: boolean)
local function async_system(command, opts, timeout, callback)
  local timer = uv.new_timer()
  local finished = false
  local handle

  local function finish(result, timed_out)
    if finished then
      return
    end
    finished = true
    if timer then
      timer:stop()
      timer:close()
      timer = nil
    end
    if handle then
      state.system_handles[handle] = nil
    end
    vim.schedule(function()
      callback(result, timed_out)
    end)
  end

  local system_opts = vim.tbl_extend("force", { text = true }, opts or {})
  handle = vim.system(command, system_opts, function(result)
    finish(result, false)
  end)
  state.system_handles[handle] = true

  if timeout then
    timer:start(timeout, 0, function()
      if finished then
        return
      end
      handle:kill(15)
      finish({
        code = 124,
        signal = 15,
        stdout = "",
        stderr = "command timed out",
      }, true)
    end)
  end
end

local function cancel_systems()
  for handle in pairs(state.system_handles) do
    pcall(handle.kill, handle, 15)
  end
  state.system_handles = {}
end

local function host_record(alias)
  for _, path in ipairs(ssh_config_paths) do
    if vim.fn.filereadable(path) == 1 then
      local current = {}
      for _, raw_line in ipairs(vim.fn.readfile(path)) do
        local line = vim.trim(raw_line)
        local names = line:match("^[Hh][Oo][Ss][Tt]%s+(.+)$")
        if names then
          current = {}
          for name in names:gmatch("%S+") do
            if not name:find("[%*%?]") and name == alias then
              current[#current + 1] = name
            end
          end
        elseif #current > 0 then
          local path_value = line:match("^#%s*Path=(.+)$")
          if path_value then
            return { name = alias, path = vim.trim(path_value), config = path }
          end
        end
      end
    end
  end
  return { name = alias, path = "" }
end

function M.host_names()
  local names = {}
  local seen = {}

  for _, path in ipairs(ssh_config_paths) do
    if vim.fn.filereadable(path) == 1 then
      local current = {}
      for _, raw_line in ipairs(vim.fn.readfile(path)) do
        local line = vim.trim(raw_line)
        local host_line = line:match("^[Hh][Oo][Ss][Tt]%s+(.+)$")
        if host_line then
          current = {}
          for name in host_line:gmatch("%S+") do
            if not name:find("[%*%?]") and not seen[name] then
              seen[name] = true
              names[#names + 1] = name
              current[#current + 1] = name
            elseif not name:find("[%*%?]") then
              current[#current + 1] = name
            end
          end
        end
      end
    end
  end

  table.sort(names)
  return names
end

local function host_picker(callback)
  local names = M.host_names()
  if #names == 0 then
    notify("No explicit SSH hosts were found in ~/.ssh/config", vim.log.levels.WARN)
    return
  end

  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks.picker then
    local items = {}
    for i, name in ipairs(names) do
      items[i] = { text = name, name = name }
    end

    Snacks.picker.pick({
      title = "Connect to remote host",
      items = items,
      format = "text",
      layout = "vertical",
      confirm = function(picker, item)
        picker:close()
        if item then
          callback(item.name)
        end
      end,
    })
    return
  end

  vim.ui.select(names, { prompt = "SSH host" }, function(name)
    if name then
      callback(name)
    end
  end)
end

local function parse_effective_config(alias, output)
  local host = host_record(alias)
  host.name = alias
  host.hostname = alias
  host.user = nil
  host.port = "22"
  host.strict_host_key_checking = nil
  host.user_known_hosts_file = nil

  for line in output:gmatch("[^\r\n]+") do
    local key, value = line:match("^(%S+)%s+(.*)$")
    if key and value then
      key = key:lower()
      if key == "hostname" then
        host.hostname = value
      elseif key == "user" then
        host.user = value
      elseif key == "port" then
        host.port = value
      elseif key == "stricthostkeychecking" then
        host.strict_host_key_checking = value:lower()
      elseif key == "userknownhostsfile" then
        host.user_known_hosts_file = value
      end
    end
  end

  return host
end

local reset_state
local abort_attempt

local function resolve_host(alias, token, callback)
  notify("Resolving SSH configuration for " .. alias .. "...")
  async_system({ "ssh", "-F", ssh_config_paths[1], "-G", alias }, nil, 5000, function(result, timed_out)
    if token ~= state.token then
      return
    end
    if timed_out or result.code ~= 0 then
      local detail = vim.trim(result.stderr or "")
      abort_attempt(
        token,
        "Could not resolve SSH host " .. alias .. (detail ~= "" and (": " .. detail) or ""),
        vim.log.levels.ERROR
      )
      return
    end
    callback(parse_effective_config(alias, result.stdout or ""))
  end)
end

local function known_hosts_path(host)
  local configured = host.user_known_hosts_file or ""
  for raw_path in configured:gmatch("%S+") do
    local path = vim.fn.expand(raw_path)
    if path ~= "/dev/null" then
      return path
    end
  end
  return vim.fn.expand("~/.ssh/known_hosts")
end

local function skips_host_key_check(host)
  return host.user_known_hosts_file == "/dev/null"
    or host.strict_host_key_checking == "no"
    or host.strict_host_key_checking == "off"
end

local function host_lookup_name(host)
  if host.port and host.port ~= "22" then
    return string.format("[%s]:%s", host.hostname, host.port)
  end
  return host.hostname
end

local function append_known_host(path, scan)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local file = io.open(path, "a")
  if not file then
    return false
  end
  file:write(scan)
  if not scan:match("\n$") then
    file:write("\n")
  end
  file:close()
  return true
end

reset_state = function()
  state.phase = "disconnected"
  state.target = "local"
  state.host = nil
  state.mount_dir = nil
  state.job_id = nil
  state.output = {}
end

abort_attempt = function(token, message, level)
  if token ~= state.token then
    return
  end
  cancel_systems()
  state.token = state.token + 1
  reset_state()
  notify(message, level or vim.log.levels.ERROR)
end

local function verify_host_key(host, token, callback)
  if skips_host_key_check(host) then
    callback(true)
    return
  end

  local known_hosts = known_hosts_path(host)
  local lookup = host_lookup_name(host)
  async_system({ "ssh-keygen", "-F", lookup, "-f", known_hosts }, nil, 2000, function(result)
    if token ~= state.token then
      return
    end
    if result.code == 0 and vim.trim(result.stdout or "") ~= "" then
      callback(true)
      return
    end

    local scan_command = { "ssh-keyscan", "-T", "5" }
    if host.port and host.port ~= "" then
      table.insert(scan_command, "-p")
      table.insert(scan_command, host.port)
    end
    table.insert(scan_command, host.hostname)

    notify("Retrieving host key for " .. host.hostname .. "...")
    async_system(scan_command, nil, 7000, function(scan_result, timed_out)
      if token ~= state.token then
        return
      end
      local scan = vim.trim(scan_result.stdout or "")
      if timed_out or scan_result.code ~= 0 or scan == "" then
        abort_attempt(
          token,
          "Could not retrieve a host key for " .. host.hostname .. " within 7 seconds",
          vim.log.levels.ERROR
        )
        return
      end

      async_system({ "ssh-keygen", "-lf", "-" }, { stdin = scan .. "\n" }, 3000, function(fp_result)
        if token ~= state.token then
          return
        end
        local fingerprint = vim.trim(fp_result.stdout or "")
        if fingerprint == "" then
          fingerprint = "fingerprint unavailable"
        end

        vim.ui.select(
          { "Add key and connect", "Cancel" },
          {
            prompt = string.format(
              "Host %s is not in %s (%s)",
              host.hostname,
              known_hosts,
              fingerprint
            ),
          },
          function(choice)
            if token ~= state.token then
              return
            end
            if choice ~= "Add key and connect" then
              abort_attempt(token, "Connection cancelled", vim.log.levels.WARN)
              return
            end
            if not append_known_host(known_hosts, scan) then
              abort_attempt(token, "Could not write " .. known_hosts, vim.log.levels.ERROR)
              return
            end
            callback(true)
          end
        )
      end)
    end)
  end)
end

local function mount_path(alias)
  local safe_alias = alias:gsub("[^%w%._-]", "_")
  return normalize(vim.fn.expand("~/.sshfs") .. "/" .. safe_alias)
end

local function remember_output(data)
  for _, line in ipairs(data or {}) do
    line = vim.trim(line)
    if line ~= "" then
      table.insert(state.output, line)
      if #state.output > 8 then
        table.remove(state.output, 1)
      end
    end
  end
end

local function stop_job()
  if state.job_id then
    vim.fn.jobstop(state.job_id)
    state.job_id = nil
  end
end

local function unmount(path, callback)
  if not path or path == "" then
    callback()
    return
  end

  local command = vim.fn.executable("fusermount") == 1 and "fusermount" or "umount"
  local args = command == "fusermount" and { command, "-u", path } or { command, path }
  async_system(args, nil, 5000, function(result)
    if result.code == 0 or vim.fn.executable("umount") ~= 1 or command == "umount" then
      callback()
      return
    end
    async_system({ "umount", path }, nil, 5000, function()
      callback()
    end)
  end)
end

local function fail_connection(message)
  local mount_dir = state.mount_dir
  stop_job()
  cancel_systems()
  state.token = state.token + 1
  reset_state()
  if mount_dir then
    unmount(mount_dir, function() end)
  end
  notify(message, vim.log.levels.ERROR)
end

local function poll_mount(host, mount_dir, token, started_at)
  if token ~= state.token or state.phase ~= "mounting" then
    return
  end

  async_system({ "mountpoint", "-q", mount_dir }, nil, 1500, function(result)
    if token ~= state.token or state.phase ~= "mounting" then
      return
    end

    if result.code == 0 then
      state.phase = "connected"
      notify(string.format("%s mounted at %s", host.name, mount_dir))
      notify("Execution target remains local; use <leader>rt to switch it to remote")
      return
    end

    if uv.now() - started_at > 10000 then
      local detail = state.output[#state.output] or "mount did not become ready"
      fail_connection("SSHFS connection failed: " .. detail)
      return
    end

    schedule_after(250, function()
      poll_mount(host, mount_dir, token, started_at)
    end)
  end)
end

local function start_mount(host, token)
  local mount_dir = mount_path(host.name)
  vim.fn.mkdir(mount_dir, "p")
  state.mount_dir = mount_dir
  state.phase = "mounting"
  state.output = {}

  local remote = host.name .. ":" .. (host.path or "")
  local command = {
    "sshfs",
    "-f",
    "-o",
    "reconnect",
    "-o",
    "ConnectTimeout=5",
    "-o",
    "ServerAliveInterval=15",
    "-o",
    "ServerAliveCountMax=3",
    remote,
    mount_dir,
  }

  notify("Connecting to " .. host.name .. "...")
  local job_id = vim.fn.jobstart(command, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(_, data)
      remember_output(data)
    end,
    on_stderr = function(_, data)
      remember_output(data)
    end,
    on_exit = function(_, code)
      if token ~= state.token then
        return
      end
      if state.phase == "connected" or state.phase == "mounting" then
        local detail = state.output[#state.output] or ("sshfs exited with code " .. tostring(code))
        fail_connection("SSHFS stopped: " .. detail)
      end
    end,
  })

  if job_id <= 0 then
    fail_connection("Could not start sshfs")
    return
  end

  state.job_id = job_id
  poll_mount(host, mount_dir, token, uv.now())
end

local function begin_connect(alias)
  if state.phase ~= "disconnected" then
    notify("Remote connection is already " .. state.phase, vim.log.levels.WARN)
    return
  end
  if vim.fn.executable("sshfs") ~= 1 then
    notify("sshfs is not installed", vim.log.levels.ERROR)
    return
  end
  if vim.fn.executable("ssh") ~= 1 then
    notify("ssh is not installed", vim.log.levels.ERROR)
    return
  end

  state.token = state.token + 1
  local token = state.token
  state.phase = "resolving"
  state.host = { name = alias }

  resolve_host(alias, token, function(host)
    if token ~= state.token then
      return
    end
    state.host = host
    state.phase = "verifying"
    verify_host_key(host, token, function(verified)
      if token ~= state.token or not verified then
        return
      end
      start_mount(host, token)
    end)
  end)
end

local function buffer_directory(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  if name == "" then
    return normalize(vim.fn.getcwd())
  end
  local path = normalize(name)
  if vim.fn.isdirectory(path) == 1 then
    return path
  end
  return normalize(vim.fn.fnamemodify(path, ":h"))
end

local function relative_to_mount(path, mount_dir)
  local absolute_path = normalize(path)
  local root = normalize(mount_dir)
  if absolute_path == root then
    return ""
  end

  local prefix = root .. "/"
  if absolute_path:sub(1, #prefix) == prefix then
    return absolute_path:sub(#prefix + 1)
  end
  return nil
end

local function remote_cd_command(local_dir, session)
  local relative = relative_to_mount(local_dir, session.mount_dir)
  if relative == nil then
    return nil, "The selected buffer is outside the mounted SSHFS tree"
  end

  local remote_path = session.host.path or ""
  if remote_path == "" or remote_path == "~" then
    local command = 'cd -- "$HOME"'
    if relative ~= "" then
      command = command .. " && cd -- " .. shell_quote(relative)
    end
    return command
  end

  remote_path = remote_path:gsub("/+$", "")
  if relative ~= "" then
    remote_path = remote_path .. "/" .. relative
  end
  return "cd -- " .. shell_quote(remote_path)
end

local function remote_picker_cwd(session)
  local current = buffer_directory(0)
  if relative_to_mount(current, session.mount_dir) then
    return current
  end
  return session.mount_dir
end

local function open_terminal_for(alias)
  local ok, Snacks = pcall(require, "snacks")
  if not ok or not Snacks.terminal then
    notify("Snacks terminal is not available", vim.log.levels.ERROR)
    return
  end

  Snacks.terminal({ "ssh", "-tt", alias }, {
    cwd = vim.fn.getcwd(),
    interactive = true,
    start_insert = true,
    auto_close = false,
  })
end

function M.setup()
  if state.setup then
    return
  end
  state.setup = true

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("ide_remote_workspace", { clear = true }),
    callback = function()
      local mount_dir = state.mount_dir
      stop_job()
      cancel_systems()
      if mount_dir then
        vim.fn.jobstart({ "fusermount", "-u", mount_dir }, { detach = true })
      end
    end,
  })
end

function M.connect(alias)
  M.setup()
  if alias and alias ~= "" then
    begin_connect(alias)
  else
    host_picker(begin_connect)
  end
end

function M.disconnect(opts)
  opts = opts or {}
  if state.phase == "disconnected" then
    if not opts.silent then
      notify("No SSHFS connection is active", vim.log.levels.WARN)
    end
    return
  end

  local mount_dir = state.mount_dir
  stop_job()
  cancel_systems()
  state.token = state.token + 1
  state.phase = "disconnecting"
  state.target = "local"
  unmount(mount_dir, function()
    reset_state()
    if not opts.silent then
      notify("Remote connection disconnected")
    end
  end)
end

function M.session()
  if state.phase ~= "connected" or not state.host or not state.mount_dir then
    return nil
  end
  return {
    host = state.host,
    name = state.host.name,
    mount_dir = state.mount_dir,
  }
end

function M.current_host_name()
  local session = M.session()
  return session and session.name or nil
end

function M.target()
  return state.target
end

function M.set_target(target)
  if target ~= "local" and target ~= "remote" then
    notify("Execution target must be local or remote", vim.log.levels.ERROR)
    return false
  end
  if target == "remote" and not M.session() then
    notify("Connect an SSHFS host before selecting remote execution", vim.log.levels.WARN)
    return false
  end

  state.target = target
  notify("Execution target: " .. target)
  return true
end

function M.toggle_target()
  return M.set_target(M.target() == "local" and "remote" or "local")
end

function M.open_files()
  local session = M.session()
  if not session then
    notify("No ready SSHFS connection is active", vim.log.levels.WARN)
    return
  end

  local ok, Snacks = pcall(require, "snacks")
  if not ok or not Snacks.picker then
    notify("Snacks picker is not available", vim.log.levels.ERROR)
    return
  end

  Snacks.picker.files({
    cwd = remote_picker_cwd(session),
    title = "Remote Files: " .. session.name,
  })
end

function M.open_grep()
  local session = M.session()
  if not session then
    notify("No ready SSHFS connection is active", vim.log.levels.WARN)
    return
  end

  local ok, Snacks = pcall(require, "snacks")
  if not ok or not Snacks.picker then
    notify("Snacks picker is not available", vim.log.levels.ERROR)
    return
  end

  Snacks.picker.grep({
    cwd = remote_picker_cwd(session),
    title = "Remote Grep: " .. session.name,
  })
end

function M.open_terminal()
  local session = M.session()
  if session then
    open_terminal_for(session.name)
    return
  end
  host_picker(open_terminal_for)
end

function M.remote_command(script, bufnr, local_dir)
  local session = M.session()
  if not session then
    notify("No ready SSHFS connection is active", vim.log.levels.WARN)
    return nil
  end

  local directory = local_dir and normalize(local_dir) or buffer_directory(bufnr)
  local cd, err = remote_cd_command(directory, session)
  if not cd then
    notify(err, vim.log.levels.ERROR)
    return nil
  end

  local remote_script = cd .. " && " .. script
  return {
    "ssh",
    session.name,
    "--",
    "bash",
    "-lc",
    shell_quote(remote_script),
  }
end

function M.remote_path(local_path)
  local session = M.session()
  if not session then
    return nil
  end

  local relative = relative_to_mount(local_path, session.mount_dir)
  if relative == nil then
    return nil
  end

  local base = session.host.path or ""
  if base == "" or base == "~" then
    return relative == "" and "$HOME" or "$HOME/" .. relative
  end
  base = base:gsub("/+$", "")
  return relative == "" and base or base .. "/" .. relative
end

function M.status()
  local name = state.host and state.host.name
  if state.phase == "disconnected" then
    return "local"
  end
  return string.format("%s:%s%s", state.target, state.phase, name and (":" .. name) or "")
end

function M.notify_status()
  notify("Remote status: " .. M.status())
end

return M
