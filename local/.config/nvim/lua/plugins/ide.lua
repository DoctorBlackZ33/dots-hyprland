local function add_unique(list, values)
  list = list or {}
  for _, value in ipairs(values) do
    if not vim.tbl_contains(list, value) then
      list[#list + 1] = value
    end
  end
  return list
end

-- Keep Compose validation local. The upstream raw GitHub endpoint is rate
-- limited, while yaml-language-server needs to read this schema repeatedly.
local docker_compose_schema = vim.uri_from_fname(
  vim.fn.stdpath("config") .. "/schemas/compose-spec.json"
)
local docker_compose_file_matches = {
  "**/docker-compose.yml",
  "**/docker-compose.yaml",
  "**/docker-compose.*.yml",
  "**/docker-compose.*.yaml",
  "**/compose.yml",
  "**/compose.yaml",
  "**/compose.*.yml",
  "**/compose.*.yaml",
}

local function hyprland_root(path)
  path = vim.fs.normalize(path or "")
  if path == "" then
    return nil
  end

  -- end4_custom is a dotfiles repository, so use its repository root as the
  -- LuaLS workspace. This keeps require("hyprland.*") resolving correctly.
  local config_root = vim.fs.root(path, { "hyprland.lua" })
  if not config_root then
    return nil
  end

  local git_root = vim.fs.root(path, { ".git" })
  if git_root and vim.fn.isdirectory(git_root .. "/dots/.config/hypr") == 1 then
    return git_root
  end

  -- This also covers the deployed ~/.config/hypr tree.
  if config_root:match("/%.config/hypr$") or config_root:match("/hypr$") then
    return config_root
  end

  return nil
end

local function existing_directories(paths)
  local result = {}
  for _, path in ipairs(paths) do
    if vim.fn.isdirectory(path) == 1 and not vim.tbl_contains(result, path) then
      result[#result + 1] = path
    end
  end
  return result
end

local function hyprland_lua_settings()
  local home = vim.env.HOME or vim.fn.expand("~")
  local source = home .. "/end4_custom/dots/.config/hypr"
  local deployed = home .. "/.config/hypr"

  return {
    Lua = {
      runtime = {
        version = "Lua 5.4",
        path = {
          "?.lua",
          "?/init.lua",
          source .. "/?.lua",
          source .. "/?/init.lua",
          deployed .. "/?.lua",
          deployed .. "/?/init.lua",
        },
      },
      workspace = {
        checkThirdParty = false,
        library = existing_directories({
          "/usr/share/hypr/stubs",
          "/usr/local/share/hypr/stubs",
          home .. "/.local/share/hypr/stubs",
          source,
          source .. "/hyprland",
          source .. "/custom",
          deployed,
          deployed .. "/hyprland",
          deployed .. "/custom",
        }),
      },
      diagnostics = {
        globals = {
          "HOME",
          "hl",
          "is_file_exists",
          "create_if_not_exists",
          "workspaceGroupSize",
        },
      },
      completion = {
        callSnippet = "Replace",
      },
      hint = {
        enable = true,
      },
    },
  }
end

return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = add_unique(opts.ensure_installed, {
        "jdtls",
        "java-debug-adapter",
        "java-test",
        "gradle-language-server",
        "checkstyle",
        "yamllint",
        "hadolint",
        "actionlint",
        "docker-language-server",
        "helm-ls",
        "kube-linter",
        "hyprls",
        "lua-language-server",
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = add_unique(opts.ensure_installed, {
        "java",
        "groovy",
        "dockerfile",
        "helm",
        "yaml",
        "hyprlang",
        "lua",
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.gradle_ls = opts.servers.gradle_ls or {}
      opts.servers.docker_language_server = {
        init_options = {
          telemetry = "off",
        },
      }

      -- The Docker extra still declares the older server names. Keep one
      -- authoritative Docker server so Compose and Dockerfile diagnostics do
      -- not arrive twice.
      opts.servers.dockerls = false
      opts.servers.docker_compose_language_service = false

      -- Hyprland's current configuration is Lua. The official stubs are
      -- loaded by this project-only server; ordinary Lua projects continue to
      -- use the normal lua_ls configuration.
      opts.servers.hyprls = {
        root_markers = { ".git", "hyprland.lua" },
      }
      opts.servers.hyprland_lua = {
        mason = false,
        cmd = { "lua-language-server" },
        filetypes = { "lua" },
        single_file_support = false,
        root_dir = function(bufnr, on_dir)
          local root = hyprland_root(vim.api.nvim_buf_get_name(bufnr))
          if root then
            on_dir(root)
          end
        end,
        settings = hyprland_lua_settings(),
      }

      -- Prevent the general Lua server from attaching to the same Hyprland
      -- buffers and producing duplicate or stub-less completion results.
      local lua_ls = opts.servers.lua_ls or {}
      local previous_root_dir = lua_ls.root_dir
      lua_ls.root_dir = function(bufnr, on_dir)
        if hyprland_root(vim.api.nvim_buf_get_name(bufnr)) then
          return
        end
        if type(previous_root_dir) == "function" then
          return previous_root_dir(bufnr, on_dir)
        end
        local root = vim.fs.root(bufnr, {
          ".luarc.json",
          ".luarc.jsonc",
          ".emmyrc.json",
          ".git",
        })
        on_dir(root or vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr)))
      end
      opts.servers.lua_ls = lua_ls
    end,
  },
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      local java_runtime_candidates = {
        vim.fn.expand "$HOME" .. "/.jdks/temurin-21.0.9/bin/java",
        vim.fn.expand "$HOME" .. "/.jdks/temurin-21/bin/java",
        "/usr/lib/jvm/java-21-openjdk/bin/java",
      }
      for _, candidate in ipairs(vim.fn.glob(vim.fn.expand "$HOME/.jdks/*/bin/java", false, true)) do
        if candidate:match("21") then
          table.insert(java_runtime_candidates, 1, candidate)
        end
      end
      local java21
      for _, candidate in ipairs(java_runtime_candidates) do
        if vim.fn.executable(candidate) == 1 then
          java21 = candidate
          break
        end
      end

      -- JDTLS itself must run on Java 21 on this host. This does not change
      -- the JDK used by Maven/Gradle projects or by launched applications.
      if java21 then
        opts.cmd = opts.cmd or {}
        local argument = "--java-executable=" .. java21
        if not vim.tbl_contains(opts.cmd, argument) then
          table.insert(opts.cmd, 2, argument)
        end
      end

      -- LazyVim's Java extra intentionally waits for Maven/Gradle markers.
      -- Keep that behavior when markers exist, but let standalone Java files
      -- still receive JDTLS using their containing directory as a workspace.
      local marker_root = opts.root_dir
      opts.root_dir = function(path)
        local root = marker_root and marker_root(path) or nil
        if root then
          return root
        end
        return vim.fs.dirname(path) or vim.fn.getcwd()
      end
    end,
  },
  {
    "mfussenegger/nvim-lint",
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.java = { "checkstyle" }
      opts.linters_by_ft.yaml = { "yamllint" }
      opts.linters_by_ft["yaml.docker-compose"] = { "yamllint", "docker_compose" }
      opts.linters_by_ft["yaml.ghaction"] = { "yamllint", "actionlint" }
      opts.linters_by_ft.dockerfile = { "hadolint" }

      opts.linters = opts.linters or {}
      opts.linters.docker_compose = {
        cmd = "docker",
        stdin = true,
        args = {
          "compose",
          "-f",
          "-",
          "config",
          "--quiet",
        },
        stream = "both",
        ignore_exitcode = true,
        parser = function(output)
          local message = vim.trim(output or "")
          if message == "" then
            return {}
          end
          return {
            {
              lnum = 0,
              col = 0,
              message = message,
              severity = vim.diagnostic.severity.ERROR,
              source = "docker compose",
            },
          }
        end,
      }
      opts.linters.checkstyle = vim.tbl_deep_extend("force", opts.linters.checkstyle or {}, {
        -- Checkstyle requires a project-specific ruleset. JDTLS remains the
        -- always-on Java diagnostic source when a project has no config.
        condition = function(ctx)
          local config = require("config.tasks").java_style_config(ctx.filename)
          if not config then
            return false
          end
          require("lint.linters.checkstyle").config_file = config
          return true
        end,
      })
    end,
  },
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.java = vim.tbl_extend("force", opts.formatters_by_ft.java or {}, {
        lsp_format = "fallback",
      })
      opts.formatters_by_ft.dockerfile = vim.tbl_extend("force", opts.formatters_by_ft.dockerfile or {}, {
        lsp_format = "fallback",
      })
      return opts
    end,
  },
  {
    "mosheavni/yaml-companion.nvim",
    ft = { "yaml", "yaml.docker-compose", "yaml.helm-values", "yaml.ghaction" },
    opts = {
      builtin_matchers = {
        kubernetes = { enabled = true },
        cloud_init = { enabled = true },
      },
      schemas = {
        {
          name = "Docker Compose",
          uri = docker_compose_schema,
        },
      },
      lspconfig = {
        settings = {
          redhat = { telemetry = { enabled = false } },
          yaml = {
            validate = true,
            format = { enable = true },
            hover = true,
            completion = true,
            schemaStore = {
              enable = true,
              url = "https://www.schemastore.org/api/json/catalog.json",
            },
            schemaDownload = { enable = true },
            schemas = {
              [docker_compose_schema] = docker_compose_file_matches,
            },
          },
        },
      },
    },
    config = function(_, opts)
      local cfg = require("yaml-companion").setup(opts)
      vim.lsp.config("yamlls", cfg)
      vim.lsp.enable("yamlls")
    end,
  },
}
