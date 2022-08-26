-- Generated using ntangle.nvim
local running = true

local limit = 0

local stack_level = 0
local next = false
local monitor_stack = false

local pause = false

local vars_id = 1
local vars_ref = {}

local frame_id = 1

local step_in

local step_out = false

local nvim_server

local hook_address

local auto_nvim

local log = require('nvimdbg.log').dap_logger("DEBUG")

local util = require('nvimdbg.util')

local M = {}
M.disconnected = false
M.frames = {}

function M.send_proxy_dap_response(request, response)
  vim.fn.rpcnotify(nvim_server, 'nvim_exec_lua',
    [[require"nvimdbg.server".send_dap_response(...)]], {request, response})
end

local function send_proxy_dap_event(event, body)
  vim.fn.rpcnotify(nvim_server, 'nvim_exec_lua',
    [[require"nvimdbg.server".send_dap_event(...)]], {event, body})
end

function M.launch(opts)
  vim.validate {
    opts = {opts, 't', true}
  }

  if opts then
    vim.validate {
      ["opts.host"] = {opts.host, "s", true},
      ["opts.port"] = {opts.port, "n", true},
    }
  end

  nvim_server = vim.fn.jobstart({vim.v.progpath, '--embed', '--headless'}, {rpc = true})
  M.nvim_server = nvim_server

  local mode = vim.fn.rpcrequest(nvim_server, "nvim_get_mode")
  assert(not mode.blocking, "Neovim is waiting for input at startup. Aborting.")

  if not hook_address then
    hook_address = vim.fn.serverstart()
  end

  vim.fn.rpcrequest(nvim_server, 'nvim_exec_lua',
    [[parent_conn_addr = ...]], {hook_address})

  local host = (opts and opts.host) or "127.0.0.1"
  local port = (opts and opts.port) or 0
  local server = vim.fn.rpcrequest(nvim_server, 'nvim_exec_lua',
    [[return require"nvimdbg.server".start_server(...)]], {host, port})

  log.debug("Server started on port " .. server.port)
  print("Server started on port " .. server.port)
  M.disconnected = false
  vim.defer_fn(M.wait_attach, 0)
  return server
end

function M.wait_attach()
  log.debug("Wait for attach..........")
  local timer = vim.loop.new_timer()
  timer:start(0, 100, vim.schedule_wrap(function()
    local has_attach = false
    for _,msg in ipairs(M.server_messages) do
      if msg.command == "attach" then
        has_attach = true
      end
    end

    if not has_attach then return end
    timer:close()
    log.debug("Begin process request, nums: ", #M.server_messages)

    local handlers = require('nvimdbg.request_handlers')
    local breakpoints = {}

    function handlers.continue(request)
      running = true

      M.send_proxy_dap_response(request, {})
    end

    function handlers.disconnect(request)
      debug.sethook()

      M.send_proxy_dap_response(request, {})

      vim.wait(1000)
      if nvim_server then
        vim.fn.jobstop(nvim_server)
        nvim_server = nil
      end
    end

    function handlers.next(request)
      local depth = 0
      while true do
        local info = debug.getinfo(depth+3, "S")
        if not info then
          break
        end
        depth = depth + 1
      end
      stack_level = depth-1

      next = true
      monitor_stack = true

      running = true

      M.send_proxy_dap_response(request, {})
    end

    function handlers.pause(request)
      pause = true

    end

    function handlers.scopes(request)
      local args = request.arguments
      local frame = M.frames[args.frameId]
      if not frame then 
        log.error("Frame not found!")
        return 
      end


      local scopes = {}

      local a = 1
      local local_scope = {}
      local_scope.name = "Locals"
      local_scope.presentationHint = "locals"
      local_scope.variablesReference = vars_id
      local_scope.expensive = false

      vars_ref[vars_id] = frame
      vars_id = vars_id + 1

      table.insert(scopes, local_scope)

      M.send_proxy_dap_response(request, {
        body = {
          scopes = scopes,
        };
      })
    end

    function handlers.setBreakpoints(request)
      local args = request.arguments
      local src_uri_path = util.get_uri_path(args.source.path)
      for line, line_bps in pairs(breakpoints) do
        line_bps[src_uri_path] = nil
      end
      local results_bps = {}

      for _, bp in ipairs(args.breakpoints) do
        breakpoints[bp.line] = breakpoints[bp.line] or {}
        local line_bps = breakpoints[bp.line]
        line_bps[src_uri_path] = true
        table.insert(results_bps, { verified = true })
        log.debug("Set breakpoint at line ", bp.line, " in ", args.source.path)
      end

      M.send_proxy_dap_response(request, {
        body = {
          breakpoints = results_bps
        }
      })
    end

    function handlers.stackTrace(request)
      local args = request.arguments
      local start_frame = args.startFrame or 0
      local max_levels = args.levels or -1


      local stack_frames = {}
      local levels = 1
      while levels <= max_levels or max_levels == -1 do
        local info = debug.getinfo(2+levels+start_frame)
        if not info then
          break
        end

        local stack_frame = {}
        stack_frame.id = frame_id
        stack_frame.name = info.name or info.what
        if info.source:sub(1, 1) == '@' then
          stack_frame.source = {
            name = info.source,
            path = vim.fn.fnamemodify(info.source:sub(2), ":p"),
          }
          stack_frame.line = info.currentline 
          stack_frame.column = 0
        end
        table.insert(stack_frames, stack_frame)
        M.frames[frame_id] = 2+levels+start_frame
        frame_id = frame_id + 1

        levels = levels + 1
      end


      M.send_proxy_dap_response(request, {
        body = {
          stackFrames = stack_frames,
          totalFrames = #stack_frames,
        };
      })
    end

    function handlers.stepIn(request)
      step_in = true

      running = true


      M.send_proxy_dap_response(request,{})
    end

    function handlers.stepOut(request)
      step_out = true
      monitor_stack = true

      local depth = 0
      while true do
        local info = debug.getinfo(depth+3, "S")
        if not info then
          break
        end
        depth = depth + 1
      end
      stack_level = depth-1

      running = true


      M.send_proxy_dap_response(request, {})

    end

    function handlers.threads(request)
      M.send_proxy_dap_response(request, {
        body = {
          threads = {
            {
              id = 1,
              name = "main"
            }
          }
        }
      })
    end

    function handlers.variables(request)
      local args = request.arguments

      local ref = vars_ref[args.variablesReference]
      local variables = {}
      if type(ref) == "number" then
        local a = 1
        local frame = ref
        while true do
          local ln, lv = debug.getlocal(frame, a)
          if not ln then
            break
          end

          if vim.startswith(ln, "(") then

          else
            local v = {}
            v.name = tostring(ln)
            v.variablesReference = 0
            if type(lv) == "table" then
              vars_ref[vars_id] = lv
              v.variablesReference = vars_id
              vars_id = vars_id + 1

            end
            v.value = tostring(lv) 

            table.insert(variables, v)
          end
          a = a + 1
        end

        local func = debug.getinfo(frame).func
        local a = 1
        while true do
          local ln,lv = debug.getupvalue(func, a)
          if not ln then break end

          if vim.startswith(ln, "(") then

          else
            local v = {}
            v.name = tostring(ln)
            v.variablesReference = 0
            if type(lv) == "table" then
              vars_ref[vars_id] = lv
              v.variablesReference = vars_id
              vars_id = vars_id + 1

            end
            v.value = tostring(lv) 

            table.insert(variables, v)
          end
          a = a + 1
        end
      elseif type(ref) == "table" then
        for ln, lv in pairs(ref) do
            local v = {}
            v.name = tostring(ln)
            v.variablesReference = 0
            if type(lv) == "table" then
              vars_ref[vars_id] = lv
              v.variablesReference = vars_id
              vars_id = vars_id + 1

            end
            v.value = tostring(lv) 

            table.insert(variables, v)
        end

      end

      M.send_proxy_dap_response(request, {
        body = {
          variables = variables,
        }
      })
    end

    debug.sethook(function(event, line)
      local i = 1
      while i <= #M.server_messages do
        local msg = M.server_messages[i]
        local f = handlers[msg.command]
        log.trace("Process server command")
        if f then
          f(msg)
        else
          log.error("Could not handle ", msg)
        end
        i = i + 1
      end

      M.server_messages = {}

      local depth = 0
      if monitor_stack then
        while true do
          local info = debug.getinfo(depth+3, "S")
          if not info then
            break
          end
          depth = depth + 1
        end
      end

      local bps = breakpoints[line]
      if event == "line" and bps then
        local info = debug.getinfo(2, "S")
        local source_path = info.source

        if source_path:sub(1, 1) == "@" or step_in then
          local path = source_path:sub(2)
          path = util.get_uri_path(path)

          if bps[path] then
            log.debug("breakpoint hit")
            send_proxy_dap_event("stopped", { reason = "breakpoint", threadId = 1 })
            running = false
            while not running do
              if M.disconnected then
                break
              end
              local i = 1
              while i <= #M.server_messages do
                local msg = M.server_messages[i]
                local f = handlers[msg.command]
                log.debug(msg)
                if f then
                  f(msg)
                else
                  log.error("Could not handle ", msg)
                end
                i = i + 1
              end

              M.server_messages = {}

              vim.wait(50)
            end

          end
        end


      elseif event == "line" and step_in then
        send_proxy_dap_event("stopped", { reason = "step", threadId = 1 })
        step_in = false


        running = false
        while not running do
          if M.disconnected then
            break
          end
          local i = 1
          while i <= #M.server_messages do
            local msg = M.server_messages[i]
            local f = handlers[msg.command]
            log.debug(msg)
            if f then
              f(msg)
            else
              log.error("Could not handle ", msg.command)
            end
            i = i + 1
          end

          M.server_messages = {}

          vim.wait(50)
        end


      elseif event == "line" and next and depth == stack_level then
        send_proxy_dap_event("stopped", { reason = "step", threadId = 1 })
        next = false
        monitor_stack = false


        running = false
        while not running do
          if M.disconnected then
            break
          end
          local i = 1
          while i <= #M.server_messages do
            local msg = M.server_messages[i]
            local f = handlers[msg.command]
            log.debug(msg)
            if f then
              f(msg)
            else
              log.error("Could not handle ", msg.command)
            end
            i = i + 1
          end

          M.server_messages = {}

          vim.wait(50)
        end


      elseif event == "line" and step_out and stack_level-1 == depth then
        send_proxy_dap_event("stopped", { reason = "step", threadId = 1 })
        step_out = false
        monitor_stack = false


        running = false
        while not running do
          if M.disconnected then
            break
          end
          local i = 1
          while i <= #M.server_messages do
            local msg = M.server_messages[i]
            local f = handlers[msg.command]
            log.debug(msg)
            if f then
              f(msg)
            else
              log.error("Could not handle " .. msg.command)
            end
            i = i + 1
          end

          M.server_messages = {}

          vim.wait(50)
        end

      elseif event == "line" and pause then
        pause = false
        send_proxy_dap_event("stopped", { reason = "pause", threadId = 1 })
        running = false
        while not running do
          if M.disconnected then
            break
          end
          local i = 1
          while i <= #M.server_messages do
            local msg = M.server_messages[i]
            local f = handlers[msg.command]
            log.debug(msg)
            if f then
              f(msg)
            else
              log.error("Could not handle " .. msg.command)
            end
            i = i + 1
          end

          M.server_messages = {}

          vim.wait(50)
        end


      end
    end, "clr")

  end))
end

M.server_messages = {}
function M.run_this(opts)
  local dap = require"dap"
  assert(dap, "nvim-dap not found. Please make sure it's installed.")

  if auto_nvim then
    vim.fn.jobstop(auto_nvim)
    auto_nvim = nil
  end

  auto_nvim = vim.fn.jobstart({vim.v.progpath, '--embed', '--headless'}, {rpc = true})

  assert(auto_nvim, "Could not create neovim instance with jobstart!")


  local mode = vim.fn.rpcrequest(auto_nvim, "nvim_get_mode")
  assert(not mode.blocking, "Neovim is waiting for input at startup. Aborting.")

  local server = vim.fn.rpcrequest(auto_nvim, "nvim_exec_lua", [[return require"osv".launch(...)]], { opts })
  vim.wait(100)

  assert(dap.adapters.nlua, "nvim-dap adapter configuration for nlua not found. Please refer to the README.md or :help osv.txt")

  local osv_config = {
    type = "nlua",
    request = "attach",
    name = "Debug current file",
    host = server.host,
    port = server.port,
  }
  dap.run(osv_config)

  dap.listeners.after['setBreakpoints']['osv'] = function(session, body)
    vim.schedule(function()
      vim.fn.rpcnotify(auto_nvim, "nvim_command", "luafile " .. vim.fn.expand("%:p"))

    end)
  end

end

function M.stop()
  debug.sethook()

  send_proxy_dap_event("terminated")
  send_proxy_dap_event("exited", { exitCode = 0 })

  if nvim_server then
    vim.fn.jobstop(nvim_server)
    nvim_server = nil
  end
  -- this is sketchy....
  running = true

  limit = 0

  stack_level = 0
  next = false
  monitor_stack = false

  pause = false

  vars_id = 1
  vars_ref = {}

  frame_id = 1
  M.frames = {}

  step_out = false

  require('nvimdbg.dap').reset_seqid()

  M.disconnected = false
end

return M
