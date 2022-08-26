local M = {}

function M.setup(conf)
  if not conf then
    return
  end

  if conf.log_level then
    require('nvimdbg.log').logger(conf.log_level)
  end
end

return M
