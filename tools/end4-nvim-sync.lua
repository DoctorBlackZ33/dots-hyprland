local delay = tonumber(vim.env.END4_NVIM_SYNC_DELAY or "2500") or 2500

vim.defer_fn(function()
  if vim.fn.exists(":Lazy") ~= 2 then
    print("end4 nvim: FAIL Lazy command is unavailable")
    vim.cmd("cquit 1")
    return
  end

  print("end4 nvim: syncing plugins from lazy-lock.json")
  local ok, error_message = pcall(vim.cmd, "Lazy! sync")
  if not ok then
    print("end4 nvim: FAIL plugin sync: " .. tostring(error_message))
    vim.cmd("cquit 1")
    return
  end

  vim.defer_fn(function()
    print("end4 nvim: plugin sync complete")
    vim.cmd("qa!")
  end, 1500)
end, delay)
