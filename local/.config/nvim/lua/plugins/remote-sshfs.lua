return {
  "nosduco/remote-sshfs.nvim",
  dependencies = {
    "folke/snacks.nvim",
    "nvim-lua/plenary.nvim",
  },
  opts = {
    ui = { picker = "snacks" },
    connections = {
      ssh_configs = {
        vim.fn.expand "$HOME" .. "/.ssh/config",
        "/etc/ssh/ssh_config",
      },
      ssh_known_hosts = vim.fn.expand "$HOME" .. "/.ssh/known_hosts",
      sshfs_args = { "-o reconnect", "-o ConnectTimeout=5" },
    },
    mounts = {
      base_dir = vim.fn.expand "$HOME" .. "/.sshfs/",
      unmount_on_exit = true,
    },
  },
}
