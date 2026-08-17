# IDE additions

This configuration keeps LazyVim as the base and adds explicit project tasks
around the existing completion, LSP, Yazi, Markdown, AI, and remote workspace
setup.

## Java

- `nvim-jdtls` uses the Java 21 runtime in `~/.jdks` when available. The JDK
  used by a Maven/Gradle project is unchanged.
- `nvim-dap`, `nvim-dap-ui`, Java Debug Adapter, Java Test, and virtual text are
  enabled through LazyVim extras.
- Blink completion is used for JDTLS completion.
- `<leader>jb` runs Maven `verify` or Gradle `build`, preferring project
  wrappers. `<leader>ji` compiles the current standalone source when no build
  tool is detected. `<leader>jt` runs the project tests.
- `<leader>jc` runs Checkstyle when a project Checkstyle configuration exists;
  `<leader>jm` runs PMD when `pmd` is available.
- `<leader>jp` starts a Java Flight Recorder capture using `jcmd`; `<leader>ja`
  starts async-profiler when `asprof` is installed.
- LazyVim's Java test and DAP mappings remain available, including `<leader>tt`
  and the standard `<leader>d...` mappings.

## SSH and remote execution

- `<leader>rc` selects an explicit host alias from the existing SSH config and
  mounts it with the asynchronous SSHFS workspace manager.
- `<leader>rf` opens a Snacks file picker rooted at the mounted host, and
  `<leader>rg` opens a remote grep picker. Normal `<leader>ff` remains local.
- `<leader>rs` opens an interactive `ssh -tt <host>` terminal in Snacks. It uses
  the same SSH aliases, keys, agents, and credentials as the shell.
- `<leader>rt` toggles the task execution target between local and the active
  mounted host. The target stays local after connecting until explicitly
  switched.
- `<leader>rd` unmounts the active host.
- `:IDERemoteStatus` reports whether the workspace is resolving, verifying,
  mounting, connected, or disconnecting.

Remote tasks use the SSH alias and run in the directory corresponding to the
mounted buffer. Host-key checks and new-host approval run asynchronously, so a
slow or unreachable host does not freeze Neovim. Credentials remain in the
existing SSH configuration; this configuration does not copy keys or install
tools on remote machines.

## YAML, Docker, Helm, and Kubernetes

- YAML uses `yaml-language-server`, SchemaStore, and `yaml-companion.nvim` for
  Kubernetes manifest and CRD schema detection. Docker Compose files receive
  the checked-in `schemas/compose-spec.json` schema locally, avoiding raw
  GitHub rate limits; `<leader>ys` can also select it manually. `<leader>yc`
  adds CRD modelines.
- `<leader>yl` runs the YAML style linter. Docker Compose buffers also run
  `docker compose config --quiet` through nvim-lint for schema/semantic
  validation; `<leader>xc` runs that validation as an explicit task.
- Dockerfiles use the official Docker language server and Hadolint.
- Helm files use `helm-ls.nvim` and the Helm language server.
- `<leader>yl`, `<leader>xl`, and `<leader>al` run YAML, Dockerfile, and GitHub
  Actions lint tasks.
- `<leader>kl`, `<leader>kd`, `<leader>kD`, `<leader>kh`, and `<leader>kb` run
  kube-linter, a client dry-run, a diff, Helm lint, and Kustomize build.
- `<leader>xb`, `<leader>xu`, and `<leader>xq` run Docker build, Compose up, and
  Compose down.

## Hyprland

- Lua files in `/home/black/end4_custom/dots/.config/hypr` use a dedicated
  LuaLS workspace with the Hyprland stubs from `/usr/share/hypr/stubs`, plus
  the source and deployed Hyprland module paths. This provides `hl.*` hover,
  diagnostics, and completion while preserving ordinary Lua project behavior.
- `hyprls` and the `hyprlang` treesitter parser are enabled for legacy
  `hyprland.conf`/`.hypr` files. The current Hyprland configuration is Lua, so
  `hyprland.lua` and its required modules are handled by LuaLS.

These deployment commands are task shortcuts, not automatic save hooks. A
cluster or container operation must be started explicitly.

Run `<leader>ih` or `:IDEHealth` to see missing host commands. Project wrappers
(`mvnw`, `gradlew`) are preferred, so Maven and Gradle do not need to be global
when a project includes its wrapper. For the Kubernetes tasks, install
`kubectl`, `helm`, and `kustomize`; for global Java builds, install Maven or
Gradle. On this Arch-based host, the command is:

    sudo pacman -S --needed kubectl helm kustomize maven gradle

PMD and async-profiler are intentionally optional because they are not
available as current Mason packages on this host.

Overseer is available with `<leader>ow`; all shortcuts above create visible
Overseer tasks whose output and status can be revisited there.

## Key groups and Yazi

Which-key labels and icons are registered for Actions (`<leader>a`), IDE
(`i`), Java (`j`), Kubernetes (`k`), Overseer (`o`), Remote (`r`), and YAML
(`y`). Yazi opens with `<leader>fy`.

Yazi's Neovim integration actions use `F1` through `F11` inside the Yazi
terminal buffer. `F1` shows help; `F2`/`F3`/`F4` open vertical, horizontal, or
tab splits; `F5`/`F6` grep or replace; `F7` cycles buffers; `F8` copies paths;
`F9` sends files to quickfix; `F10` changes the working directory; and `F11`
picks a window.
