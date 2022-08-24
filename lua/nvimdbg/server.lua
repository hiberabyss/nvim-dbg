local log = require('nvimdbg.log').log
local make_event = require('dap.builder').make_event
local make_response = require('dap.builder').make_response

local client
local debug_hook_conn 
local disconnected = require('osv').disconnected

local M = {}

function M.sendDAP(msg)
  local succ, encoded = pcall(vim.fn.json_encode, msg)

  if succ then
    local bin_msg = "Content-Length: " .. string.len(encoded) .. "\r\n\r\n" .. encoded

    client:write(bin_msg)
    -- log("SendDap: " .. bin_msg)
  else
    log('Fail to encode lua msg: ' .. encoded)
  end
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
        log("Adapter fail to decode json")
      end

      -- log("Adapter decoded: " .. vim.pretty_print(decoded))

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
      local len = read_header()
      local msg = read_body(len.content_length)
      log("Adapter received msg: " .. vim.inspect(msg))

      M.sendDAP(make_response(msg, {
        body = {}
      }))

      M.sendDAP(make_event('initialized'))

      while true do
        local msg
        do
          local len = read_header()
          msg = read_body(len.content_length)
        end

        if debug_hook_conn then
          vim.fn.rpcrequest(debug_hook_conn, "nvim_exec_lua", [[table.insert(require"osv".server_messages, ...)]], {msg})
        end

      end
    end)

    sock:read_start(vim.schedule_wrap(function(err, chunk)
      if chunk then
        tcp_data = tcp_data .. chunk
        coroutine.resume(dap_read)
      else
        log('Adapter error, Fail to parse request!')
        vim.fn.rpcrequest(debug_hook_conn, "nvim_exec_lua",
          [[require"osv".disconnected = true]], {})

        sock:shutdown()
        sock:close()
      end
    end))

  end)

  log("Adapter server started on " .. server:getsockname().port)
  log("Hook Adress: " .. debug_hook_conn_address)

  if debug_hook_conn_address then
    debug_hook_conn = vim.fn.sockconnect("pipe", debug_hook_conn_address, {rpc = true})
  end

  return {
    host = host,
    port = server:getsockname().port
  }
end

return M
