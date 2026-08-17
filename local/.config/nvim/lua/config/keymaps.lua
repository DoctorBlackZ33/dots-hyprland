-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local function command(name)
  return "<cmd>" .. name .. "<cr>"
end

require("config.tasks").setup()

-- Java: build, test, static analysis, and profiling.
vim.keymap.set("n", "<leader>jb", command "IDEJavaBuild", { desc = "Java build" })
vim.keymap.set("n", "<leader>ji", command "IDEJavaCompile", { desc = "Java compile" })
vim.keymap.set("n", "<leader>jt", command "IDEJavaTest", { desc = "Java test" })
vim.keymap.set("n", "<leader>jc", command "IDEJavaCheckstyle", { desc = "Java Checkstyle" })
vim.keymap.set("n", "<leader>jm", command "IDEJavaPMD", { desc = "Java PMD" })
vim.keymap.set("n", "<leader>jp", command "IDEJavaJFR", { desc = "Java JFR profile" })
vim.keymap.set("n", "<leader>ja", command "IDEJavaAsyncProfile", { desc = "Java async-profiler" })

-- SSHFS mount management and explicit local/remote execution.
vim.keymap.set("n", "<leader>rc", command "IDERemoteConnect", { desc = "Remote connect" })
vim.keymap.set("n", "<leader>rd", command "IDERemoteDisconnect", { desc = "Remote disconnect" })
vim.keymap.set("n", "<leader>rs", command "IDERemoteTerminal", { desc = "Remote terminal" })
vim.keymap.set("n", "<leader>rt", command "IDERemoteToggleTarget", { desc = "Toggle execution target" })
vim.keymap.set("n", "<leader>rf", command "IDERemoteFiles", { desc = "Remote files" })
vim.keymap.set("n", "<leader>rg", command "IDERemoteGrep", { desc = "Remote grep" })

-- YAML, Docker, Helm, and Kubernetes task shortcuts. All mutating cluster or
-- container operations remain explicit commands rather than save hooks.
vim.keymap.set("n", "<leader>yl", command "IDEYamlLint", { desc = "YAML lint" })
vim.keymap.set("n", "<leader>xc", command "IDEComposeValidate", { desc = "Docker Compose schema" })
vim.keymap.set("n", "<leader>al", command "IDEActionlint", { desc = "GitHub Actions lint" })
vim.keymap.set("n", "<leader>xl", command "IDEDockerLint", { desc = "Dockerfile lint" })
vim.keymap.set("n", "<leader>xb", command "IDEDockerBuild", { desc = "Docker build" })
vim.keymap.set("n", "<leader>xu", command "IDEDockerComposeUp", { desc = "Docker Compose up" })
vim.keymap.set("n", "<leader>xq", command "IDEDockerComposeDown", { desc = "Docker Compose down" })
vim.keymap.set("n", "<leader>kl", command "IDEKubeLint", { desc = "Kubernetes lint" })
vim.keymap.set("n", "<leader>kd", command "IDEKubeDryRun", { desc = "Kubernetes dry-run" })
vim.keymap.set("n", "<leader>kD", command "IDEKubeDiff", { desc = "Kubernetes diff" })
vim.keymap.set("n", "<leader>kh", command "IDEHelmLint", { desc = "Helm lint" })
vim.keymap.set("n", "<leader>kb", command "IDEKustomizeBuild", { desc = "Kustomize build" })
vim.keymap.set("n", "<leader>ih", command "IDEHealth", { desc = "IDE prerequisite health" })

-- yaml-companion is loaded on YAML buffers, so these mappings degrade
-- gracefully when invoked from another filetype.
vim.keymap.set("n", "<leader>ys", function()
  local ok, yaml_companion = pcall(require, "yaml-companion")
  if ok then
    yaml_companion.open_ui_select()
  else
    vim.notify("yaml-companion is available in YAML buffers", vim.log.levels.WARN, { title = "IDE YAML" })
  end
end, { desc = "YAML schema picker" })

vim.keymap.set("n", "<leader>yc", function()
  local ok, yaml_companion = pcall(require, "yaml-companion")
  if ok then
    yaml_companion.add_crd_modelines()
  else
    vim.notify("yaml-companion is available in YAML buffers", vim.log.levels.WARN, { title = "IDE YAML" })
  end
end, { desc = "Add CRD schema modelines" })
