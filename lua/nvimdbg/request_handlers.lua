local handlers = {}
local log = require('nvimdbg.log').logger()

local M = require('osv')

function handlers.attach(request)
  M.send_proxy_dap_response(request, {})
end

function handlers.evaluate(request)
  log.debug('Begin process evaluate')
  local args = request.arguments
  if args.context == "repl" then
    local frame = M.frames[args.frameId]
    -- what is this abomination...
    --              a former c++ programmer
    local a = 1
    local prev
    local cur = {}
    local first = cur

    while true do
      local succ, ln, lv = pcall(debug.getlocal, frame+1, a)
      if not succ then
        break
      end

      if not ln then
        prev = cur

        cur = {}
        setmetatable(prev, {
          __index = cur
        })

        frame = frame + 1
        a = 1
      else
        cur[ln] = lv
        a = a + 1
      end
    end

    setmetatable(cur, {
      __index = _G
    })

    local succ, f = pcall(loadstring, "return " .. args.expression)
    if succ and f then
      setfenv(f, first)
    end

    local result_repl
    if succ then
      succ, result_repl = pcall(f)
    else
      result_repl = f
    end

    M.send_proxy_dap_response(request, {
      body = {
        result = vim.inspect(result_repl),
        variablesReference = 0,
      }
    })
  else
    log.error("evaluate context " .. args.context .. " not supported!")
  end
end

return handlers
