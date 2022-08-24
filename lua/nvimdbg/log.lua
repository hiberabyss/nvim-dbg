local M = {}

local log_filename

function M.init(conf)
  if conf and conf.log then
    log_filename = vim.fn.stdpath("data") .. "/osv.log"
  end
end

function M.log(str)
  log_filename = vim.fn.stdpath("data") .. "/osv.log"
  if log_filename then
    local f = io.open(log_filename, "a")
    if f then
      f:write(str .. "\n")
      f:close()
    end
  end

  if debug_output then
    table.insert(debug_output, tostring(str))
  else
    -- print(str)
  end
end

return M
