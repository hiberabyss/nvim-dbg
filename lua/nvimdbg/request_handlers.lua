local handlers = {}

local M = require('osv')

function handlers.attach(request)
  M.send_proxy_dap_response(request, {})
end

--[[ function handlers.initialize(request)
  M.send_proxy_dap_response(request, {body = {}})
  M.send_proxy_dap_event('initialized')
end ]]

return handlers
