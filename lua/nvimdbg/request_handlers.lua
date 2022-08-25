local handlers = {}

local osv = require('osv')

local function sendProxyDAP(data)
  vim.fn.rpcnotify(osv.nvim_server, 'nvim_exec_lua',
    [[require"nvimdbg.server".sendDAP(...)]], {data})
end

return handlers
