return {
  "mikavilpas/yazi.nvim",
  event = "VeryLazy",
  keys = {
    {
      "<leader>fy",
      function()
        require("yazi").yazi()
      end,
      desc = "Yazi file manager",
    },
  },
  dependencies = {
    "nvim-lua/plenary.nvim",
  },
  ---@type YaziConfig
  opts = {
    keymaps = {
      show_help = "<f1>",
      -- Keep these integration actions out of Yazi's normal Ctrl/Tab input.
      open_file_in_vertical_split = "<f2>",
      open_file_in_horizontal_split = "<f3>",
      open_file_in_tab = "<f4>",
      grep_in_directory = "<f5>",
      replace_in_directory = "<f6>",
      cycle_open_buffers = "<f7>",
      copy_relative_path_to_selected_files = "<f8>",
      send_to_quickfix_list = "<f9>",
      change_working_directory = "<f10>",
      open_and_pick_window = "<f11>",
    },
  },
}
