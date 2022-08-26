local M = {}

function M.dap_logger(level)
  local log = require('dap.log')
  assert(log, 'nvim-dap log module not found!')

  local logger = log.create_logger('osv.log')
  if level then
    logger.set_level(level)
  end

  return logger
end

return M
