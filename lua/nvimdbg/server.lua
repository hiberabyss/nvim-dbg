local log = require('nvimdbg.log').logger()
local dbg_dap = require('nvimdbg.dap')

local client
local debug_hook_conn 
local disconnected = require('osv').disconnected

local M = {}

function M.send_dap_response(request, response)
  M.sendDAP(dbg_dap.make_response(request, response))
end

function M.send_dap_event(event, body)
  M.sendDAP(dbg_dap.make_event(event, body))
end

function do_initialize(request)
  M.send_dap_response(request, {body = {}})
  M.send_dap_event('initialized')
end

function M.sendDAP(msg)
  local succ, encoded = pcall(vim.fn.json_encode, msg)

  if succ then
    local bin_msg = "Content-Length: " .. string.len(encoded) .. "\r\n\r\n" .. encoded

    client:write(bin_msg)
    log.debug("Response: ", msg)
  else
    log.error('Fail to encode lua msg: ' .. encoded)
  end
end

function parent_run_lua(code, args)
  return vim.fn.rpcrequest(debug_hook_conn, "nvim_exec_lua", code, args)
end

function M.start_server(host, port)
  local server = vim.loop.new_tcp()

  server:bind(host, port)

  server:listen(128, function(err)
    disconnected = false

    local sock = vim.loop.new_tcp()
    server:accept(sock)

    local tcp_data = ""

    client = sock

    local function read_body(length)
      while string.len(tcp_data) < length do
        coroutine.yield()
      end

      local body = string.sub(tcp_data, 1, length)

      local succ, decoded = pcall(vim.fn.json_decode, body)
      if not succ then
        log.error("Adapter fail to decode json")
      end

      tcp_data = string.sub(tcp_data, length+1)

      return decoded
    end

    local function read_header()
      while not string.find(tcp_data, "\r\n\r\n") do
        coroutine.yield()
      end
      local content_length = string.match(tcp_data, "^Content%-Length: (%d+)")

      local _, sep = string.find(tcp_data, "\r\n\r\n")
      tcp_data = string.sub(tcp_data, sep+1)

      return {
        content_length = tonumber(content_length),
      }
    end

    local dap_read = coroutine.create(function()
      while true do
        local len = read_header()
        local msg = read_body(len.content_length)

        log.debug("Adapter received msg: ", msg)

        if dbg_dap.is_initialize(msg) then
          do_initialize(msg)
        else
          parent_run_lua([[table.insert(require"osv".server_messages, ...)]], {msg})
        end
      end
    end)

    sock:read_start(vim.schedule_wrap(function(err, chunk)
      tcp_data = tcp_data .. chunk
      coroutine.resume(dap_read)
    end))

  end)

  log.debug("Adapter server started on " .. server:getsockname().port)
  log.debug("Hook Adress: " .. parent_conn_addr)

  if not parent_conn_addr then
    log.error("Fail to get parent connect address!")
  end

  debug_hook_conn = vim.fn.sockconnect("pipe", parent_conn_addr, {rpc = true})
  if not debug_hook_conn then
    log.error("Fail to connect to parent neovim instance!")
  end

  return {
    host = host,
    port = server:getsockname().port
  }
end

return M
