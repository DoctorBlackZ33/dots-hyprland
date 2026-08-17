local M = {}

local root_markers = {
  ".git",
  "pom.xml",
  "mvnw",
  "build.gradle",
  "build.gradle.kts",
  "gradlew",
  "settings.gradle",
  "settings.gradle.kts",
  "Makefile",
  "Dockerfile",
  "Containerfile",
  "compose.yaml",
  "compose.yml",
  "docker-compose.yaml",
  "docker-compose.yml",
  "Chart.yaml",
  "kustomization.yaml",
  "kustomization.yml",
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "IDE task" })
end

local function normalize(path)
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function file_exists(path)
  return vim.fn.filereadable(path) == 1
end

local function directory_exists(path)
  return vim.fn.isdirectory(path) == 1
end

local function append_args(command, args)
  local result = vim.list_extend({}, command)
  vim.list_extend(result, args)
  return result
end

local function project_root_from_path(path)
  local root = vim.fs.root(path, root_markers)
  return root and normalize(root) or normalize(vim.fn.getcwd())
end

local function current_path(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  if name == "" then
    return normalize(vim.fn.getcwd())
  end
  return normalize(name)
end

local function current_directory(bufnr)
  local path = current_path(bufnr)
  if directory_exists(path) then
    return path
  end
  return normalize(vim.fn.fnamemodify(path, ":h"))
end

local function relative_path(root, path)
  local absolute_root = normalize(root)
  local absolute_path = normalize(path)
  if absolute_path == absolute_root then
    return "."
  end

  local prefix = absolute_root .. "/"
  if absolute_path:sub(1, #prefix) == prefix then
    return absolute_path:sub(#prefix + 1)
  end
  return nil
end

local function wrapper_is_executable(path)
  return file_exists(path) and vim.fn.getfperm(path):match("x") ~= nil
end

local function wrapper_command(root, wrapper, args)
  local path = root .. "/" .. wrapper
  if not file_exists(path) then
    return nil
  end

  local command = wrapper_is_executable(path) and { "./" .. wrapper } or { "bash", wrapper }
  return append_args(command, args)
end

local function external_command(command, args)
  if vim.fn.executable(command) ~= 1 then
    return nil
  end
  return append_args({ command }, args)
end

local function java_tool(root)
  if file_exists(root .. "/pom.xml") or file_exists(root .. "/mvnw") then
    return "maven"
  end
  if file_exists(root .. "/build.gradle")
    or file_exists(root .. "/build.gradle.kts")
    or file_exists(root .. "/gradlew")
    or file_exists(root .. "/settings.gradle")
    or file_exists(root .. "/settings.gradle.kts")
  then
    return "gradle"
  end
  return nil
end

local function task_name(name)
  local remote = require("config.remote")
  local host = remote.current_host_name()
  if remote.target() == "remote" and host then
    return name .. " • " .. host
  end
  return name
end

local function start_task(name, command, cwd)
  if not command or #command == 0 then
    notify("No command is available for this task", vim.log.levels.ERROR)
    return nil
  end

  local ok, overseer = pcall(require, "overseer")
  if not ok then
    notify("Overseer is not loaded; run :Lazy load overseer.nvim", vim.log.levels.ERROR)
    return nil
  end

  local task = overseer.new_task({
    name = name,
    cmd = command,
    cwd = cwd,
    components = { "default" },
  })
  task:start()
  return task
end

local function run_target(name, local_command, remote_script, opts)
  opts = opts or {}
  local root = opts.cwd or M.project_root(opts.bufnr)
  local remote = require("config.remote")

  if remote.target() == "remote" then
    local command = remote.remote_command(remote_script, opts.bufnr, root)
    if not command then
      return nil
    end
    return start_task(task_name(name), command, vim.fn.getcwd())
  end

  return start_task(name, local_command, root)
end

function M.project_root(bufnr)
  return project_root_from_path(current_path(bufnr or 0))
end

function M.java_style_config(filename)
  local path = filename and filename ~= "" and filename or current_path(0)
  local root = project_root_from_path(path)
  local candidates = {
    "checkstyle.xml",
    ".checkstyle.xml",
    "config/checkstyle/checkstyle.xml",
    "config/checkstyle/google_checks.xml",
    "config/checkstyle/sun_checks.xml",
    "config/checkstyle/checkstyle-suppressions.xml",
  }
  for _, candidate in ipairs(candidates) do
    local config = root .. "/" .. candidate
    if file_exists(config) then
      return config
    end
  end
  return nil
end

function M.java_build(kind)
  local bufnr = 0
  local root = M.project_root(bufnr)
  local tool = java_tool(root)
  local local_command
  local maven_args = kind == "test" and { "test" } or { "verify" }
  local gradle_args = kind == "test" and { "test" } or { "build" }

  if tool == "maven" then
    local_command = wrapper_command(root, "mvnw", maven_args) or external_command("mvn", maven_args)
  elseif tool == "gradle" then
    local_command = wrapper_command(root, "gradlew", gradle_args) or external_command("gradle", gradle_args)
  end

  local maven_script = kind == "test" and "test" or "verify"
  local gradle_script = kind == "test" and "test" or "build"
  local remote_script = string.format(
    [[
if [ -x ./mvnw ]; then ./mvnw %s;
elif [ -f ./mvnw ]; then bash ./mvnw %s;
elif [ -x ./gradlew ]; then ./gradlew %s;
elif [ -f ./gradlew ]; then bash ./gradlew %s;
elif [ -f pom.xml ] && command -v mvn >/dev/null 2>&1; then mvn %s;
elif ( [ -f build.gradle ] || [ -f build.gradle.kts ] ) && command -v gradle >/dev/null 2>&1; then gradle %s;
else echo 'No Maven or Gradle wrapper/system command found' >&2; exit 127; fi]],
    maven_script,
    maven_script,
    gradle_script,
    gradle_script,
    maven_script,
    gradle_script
  )

  return run_target("Java: " .. (kind == "test" and "test" or "build"), local_command, remote_script, {
    bufnr = bufnr,
    cwd = root,
  })
end

function M.java_compile()
  local bufnr = 0
  local root = M.project_root(bufnr)
  if java_tool(root) then
    return M.java_build("build")
  end

  local file = vim.api.nvim_buf_get_name(bufnr)
  local relative = relative_path(root, file)
  if not relative or not relative:match("%.java$") then
    notify("Open a Java source file or a Maven/Gradle project", vim.log.levels.WARN)
    return
  end

  local remote = require("config.remote")
  local local_command = {
    "bash",
    "-lc",
    "mkdir -p target/classes && javac -d target/classes " .. remote.shell_quote(relative),
  }
  local remote_script = "mkdir -p target/classes && javac -d target/classes " .. remote.shell_quote(relative)
  return run_target("Java: compile current source", local_command, remote_script, { bufnr = bufnr, cwd = root })
end

function M.java_checkstyle()
  local bufnr = 0
  local root = M.project_root(bufnr)
  local config = M.java_style_config(vim.api.nvim_buf_get_name(bufnr))
  if not config then
    notify("No project Checkstyle config found", vim.log.levels.WARN)
    return
  end

  local sources = {}
  for _, directory in ipairs({ "src/main/java", "src/test/java" }) do
    if directory_exists(root .. "/" .. directory) then
      sources[#sources + 1] = directory
    end
  end
  if #sources == 0 then
    sources = { "." }
  end

  local local_command = { "checkstyle", "-f", "plain", "-c", config }
  vim.list_extend(local_command, sources)
  local remote_config = relative_path(root, config) or "checkstyle.xml"
  local remote_script = "checkstyle -f plain -c " .. require("config.remote").shell_quote(remote_config)
  for _, source in ipairs(sources) do
    remote_script = remote_script .. " " .. require("config.remote").shell_quote(source)
  end

  return run_target("Java: Checkstyle", local_command, remote_script, { bufnr = bufnr, cwd = root })
end

function M.java_pmd()
  local bufnr = 0
  local root = M.project_root(bufnr)
  local source = directory_exists(root .. "/src/main/java") and "src/main/java" or "."
  local local_command = {
    "pmd",
    "check",
    "--format",
    "text",
    "--rulesets",
    "rulesets/java/quickstart.xml",
    "--dir",
    source,
  }
  local remote_script = "pmd check --format text --rulesets rulesets/java/quickstart.xml --dir "
    .. require("config.remote").shell_quote(source)

  return run_target("Java: PMD", local_command, remote_script, { bufnr = bufnr, cwd = root })
end

local function prompt_pid(prompt, callback)
  vim.ui.input({ prompt = prompt }, function(pid)
    if not pid or pid == "" then
      return
    end
    if not pid:match("^%d+$") then
      notify("PID must contain only digits", vim.log.levels.ERROR)
      return
    end
    callback(pid)
  end)
end

function M.java_jfr()
  prompt_pid("JVM PID for JFR: ", function(pid)
    vim.ui.input({ prompt = "JFR duration (e.g. 60s): ", default = "60s" }, function(duration)
      if not duration or not duration:match("^%d+[smh]$") then
        notify("Duration must look like 60s, 5m, or 1h", vim.log.levels.ERROR)
        return
      end

      local root = M.project_root(0)
      local filename = "nvim-profile-" .. os.date("%Y%m%d-%H%M%S") .. ".jfr"
      local local_command = {
        "jcmd",
        pid,
        "JFR.start",
        "name=nvim-profile",
        "settings=profile",
        "duration=" .. duration,
        "filename=" .. filename,
      }
      local remote_script = table.concat({
        "jcmd",
        pid,
        "JFR.start",
        "name=nvim-profile",
        "settings=profile",
        "duration=" .. duration,
        "filename=" .. require("config.remote").shell_quote(filename),
      }, " ")
      run_target("Java: JFR profile", local_command, remote_script, { bufnr = 0, cwd = root })
    end)
  end)
end

function M.java_async_profile()
  prompt_pid("JVM PID for async-profiler: ", function(pid)
    vim.ui.input({ prompt = "Duration in seconds: ", default = "30" }, function(duration)
      if not duration or not duration:match("^%d+$") then
        notify("Duration must contain only digits", vim.log.levels.ERROR)
        return
      end

      local root = M.project_root(0)
      local filename = "nvim-async-profile-" .. os.date("%Y%m%d-%H%M%S") .. ".html"
      local local_command = { "asprof", "-d", duration, "-f", filename, pid }
      local remote = require("config.remote")
      local remote_script = table.concat({
        "asprof",
        "-d",
        duration,
        "-f",
        remote.shell_quote(filename),
        pid,
      }, " ")
      run_target("Java: async-profiler", local_command, remote_script, { bufnr = 0, cwd = root })
    end)
  end)
end

local function current_file_relative(root, bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr or 0)
  if path == "" then
    return nil
  end
  return relative_path(root, path)
end

function M.yaml_lint()
  local bufnr = 0
  local root = M.project_root(bufnr)
  local file = current_file_relative(root, bufnr) or "."
  local remote = require("config.remote")
  return run_target(
    "YAML: lint",
    { "yamllint", file },
    "yamllint " .. remote.shell_quote(file),
    { bufnr = bufnr, cwd = root }
  )
end

function M.docker_compose_validate()
  local bufnr = 0
  local root = M.project_root(bufnr)
  local file = current_file_relative(root, bufnr)
  if not file then
    notify("Open a Docker Compose YAML file first", vim.log.levels.WARN)
    return
  end

  local remote = require("config.remote")
  return run_target(
    "Docker Compose: schema validation",
    { "docker", "compose", "-f", file, "config", "--quiet" },
    "docker compose -f " .. remote.shell_quote(file) .. " config --quiet",
    { bufnr = bufnr, cwd = root }
  )
end

function M.docker_lint()
  local bufnr = 0
  local root = M.project_root(bufnr)
  local file = current_file_relative(root, bufnr) or "Dockerfile"
  local remote = require("config.remote")
  return run_target(
    "Docker: hadolint",
    { "hadolint", file },
    "hadolint " .. remote.shell_quote(file),
    { bufnr = bufnr, cwd = root }
  )
end

function M.actionlint()
  local bufnr = 0
  local root = M.project_root(bufnr)
  local file = current_file_relative(root, bufnr) or ".github/workflows"
  local remote = require("config.remote")
  return run_target(
    "GitHub Actions: actionlint",
    { "actionlint", file },
    "actionlint " .. remote.shell_quote(file),
    { bufnr = bufnr, cwd = root }
  )
end

function M.kube_lint()
  local root = M.project_root(0)
  return run_target(
    "Kubernetes: kube-linter",
    { "kube-linter", "lint", "." },
    "kube-linter lint .",
    { bufnr = 0, cwd = root }
  )
end

function M.kube_dry_run()
  local root = M.project_root(0)
  return run_target(
    "Kubernetes: client dry-run",
    { "kubectl", "apply", "--dry-run=client", "-f", "." },
    "kubectl apply --dry-run=client -f .",
    { bufnr = 0, cwd = root }
  )
end

function M.kube_diff()
  local root = M.project_root(0)
  return run_target(
    "Kubernetes: diff",
    { "kubectl", "diff", "-f", "." },
    "kubectl diff -f .",
    { bufnr = 0, cwd = root }
  )
end

function M.helm_lint()
  local bufnr = 0
  local root = M.project_root(bufnr)
  vim.ui.input({ prompt = "Helm chart path: ", default = "." }, function(chart)
    if not chart or chart == "" then
      return
    end
    local remote = require("config.remote")
    run_target(
      "Helm: lint",
      { "helm", "lint", chart },
      "helm lint " .. remote.shell_quote(chart),
      { bufnr = bufnr, cwd = root }
    )
  end)
end

function M.kustomize_build()
  local root = M.project_root(0)
  return run_target(
    "Kustomize: build",
    { "kubectl", "kustomize", "." },
    "kubectl kustomize .",
    { bufnr = 0, cwd = root }
  )
end

local function has_compose_file(root)
  for _, name in ipairs({ "compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml" }) do
    if file_exists(root .. "/" .. name) then
      return true
    end
  end
  return false
end

function M.docker_build()
  local root = M.project_root(0)
  local default_tag = vim.fn.fnamemodify(root, ":t"):gsub("[^%w_.-]", "-"):lower()
  vim.ui.input({ prompt = "Docker image tag: ", default = default_tag }, function(tag)
    if not tag or tag == "" then
      return
    end
    if not tag:match("^[%w_.:/%-]+$") then
      notify("Image tag contains unsupported characters", vim.log.levels.ERROR)
      return
    end

    local remote = require("config.remote")
    local local_command = has_compose_file(root)
        and { "docker", "compose", "build" }
      or { "docker", "build", "-t", tag, "." }
    local remote_script = has_compose_file(root)
        and "docker compose build"
      or "docker build -t " .. remote.shell_quote(tag) .. " ."
    run_target("Docker: build", local_command, remote_script, { bufnr = 0, cwd = root })
  end)
end

function M.docker_compose_up()
  local root = M.project_root(0)
  return run_target(
    "Docker Compose: up",
    { "docker", "compose", "up", "--build" },
    "docker compose up --build",
    { bufnr = 0, cwd = root }
  )
end

function M.docker_compose_down()
  local root = M.project_root(0)
  return run_target(
    "Docker Compose: down",
    { "docker", "compose", "down" },
    "docker compose down",
    { bufnr = 0, cwd = root }
  )
end

function M.health()
  local commands = {
    "java",
    "javac",
    "jcmd",
    "jfr",
    "docker",
    "ssh",
    "sshm",
    "hyprls",
    "lua-language-server",
    "yamllint",
    "mvn",
    "gradle",
    "kubectl",
    "helm",
    "kustomize",
  }
  local missing = {}
  for _, command in ipairs(commands) do
    if vim.fn.executable(command) ~= 1 then
      missing[#missing + 1] = command
    end
  end

  local has_java21 = vim.fn.executable(vim.fn.expand "$HOME/.jdks/temurin-21.0.9/bin/java") == 1
    or vim.fn.executable(vim.fn.expand "$HOME/.jdks/temurin-21/bin/java") == 1
    or vim.fn.executable "/usr/lib/jvm/java-21-openjdk/bin/java" == 1
  if not has_java21 then
    for _, candidate in ipairs(vim.fn.glob(vim.fn.expand "$HOME/.jdks/*/bin/java", false, true)) do
      if candidate:match("21") and vim.fn.executable(candidate) == 1 then
        has_java21 = true
        break
      end
    end
  end
  if not has_java21 then
    missing[#missing + 1] = "JDK 21 (JDTLS runtime)"
  end

  if #missing == 0 then
    notify("Core IDE command-line prerequisites are available")
  else
    notify("Missing prerequisites: " .. table.concat(missing, ", "), vim.log.levels.WARN)
  end
end

function M.setup()
  if M._setup then
    return
  end
  M._setup = true

  local commands = {
    IDEJavaBuild = function()
      M.java_build("build")
    end,
    IDEJavaCompile = M.java_compile,
    IDEJavaTest = function()
      M.java_build("test")
    end,
    IDEJavaCheckstyle = M.java_checkstyle,
    IDEJavaPMD = M.java_pmd,
    IDEJavaJFR = M.java_jfr,
    IDEJavaAsyncProfile = M.java_async_profile,
    IDEYamlLint = M.yaml_lint,
    IDEComposeValidate = M.docker_compose_validate,
    IDEDockerLint = M.docker_lint,
    IDEActionlint = M.actionlint,
    IDEKubeLint = M.kube_lint,
    IDEKubeDryRun = M.kube_dry_run,
    IDEKubeDiff = M.kube_diff,
    IDEHelmLint = M.helm_lint,
    IDEKustomizeBuild = M.kustomize_build,
    IDEDockerBuild = M.docker_build,
    IDEDockerComposeUp = M.docker_compose_up,
    IDEDockerComposeDown = M.docker_compose_down,
    IDEHealth = M.health,
    IDERemoteConnect = function(opts)
      local alias = opts.args ~= "" and opts.args or nil
      require("config.remote").connect(alias)
    end,
    IDERemoteDisconnect = function()
      require("config.remote").disconnect()
    end,
    IDERemoteTerminal = function()
      require("config.remote").open_terminal()
    end,
    IDERemoteToggleTarget = function()
      require("config.remote").toggle_target()
    end,
    IDERemoteFiles = function()
      require("config.remote").open_files()
    end,
    IDERemoteGrep = function()
      require("config.remote").open_grep()
    end,
    IDERemoteStatus = function()
      require("config.remote").notify_status()
    end,
  }

  for name, callback in pairs(commands) do
    if vim.fn.exists(":" .. name) == 0 then
      local command_opts = { desc = "IDE: " .. name }
      if name == "IDERemoteConnect" then
        command_opts.nargs = "?"
        command_opts.complete = function()
          return require("config.remote").host_names()
        end
      end
      vim.api.nvim_create_user_command(name, callback, command_opts)
    end
  end
end

return M
