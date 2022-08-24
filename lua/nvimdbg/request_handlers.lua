local handlers = {}

function handlers.attach(request)
  sendProxyDAP(make_response(request, {}))
end


function handlers.continue(request)
  running = true

  sendProxyDAP(make_response(request,{}))
end

function handlers.disconnect(request)
  debug.sethook()

  sendProxyDAP(make_response(request, {}))

  vim.wait(1000)
  if nvim_server then
    vim.fn.jobstop(nvim_server)
    nvim_server = nil
  end
end

function handlers.evaluate(request)
  local args = request.arguments
  if args.context == "repl" then
    local frame = frames[args.frameId]
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

    sendProxyDAP(make_response(request, {
          body = {
            result = vim.inspect(result_repl),
            variablesReference = 0,
          }
      }))
  else
    log("evaluate context " .. args.context .. " not supported!")
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

  sendProxyDAP(make_response(request, {}))
end

function handlers.pause(request)
  pause = true

end

function handlers.scopes(request)
  local args = request.arguments
  local frame = frames[args.frameId]
  if not frame then 
    log("Frame not found!")
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

  sendProxyDAP(make_response(request,{
        body = {
          scopes = scopes,
        };
    }))
end

function handlers.setBreakpoints(request)
  local args = request.arguments
  for line, line_bps in pairs(breakpoints) do
    line_bps[vim.uri_from_fname(args.source.path:lower())] = nil
  end
  local results_bps = {}

  for _, bp in ipairs(args.breakpoints) do
    breakpoints[bp.line] = breakpoints[bp.line] or {}
    local line_bps = breakpoints[bp.line]
    line_bps[vim.uri_from_fname(args.source.path:lower())] = true
    table.insert(results_bps, { verified = true })
    log("Set breakpoint at line " .. bp.line .. " in " .. args.source.path)
  end

  sendProxyDAP(make_response(request, {
        body = {
          breakpoints = results_bps
        }
    }))


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
    frames[frame_id] = 2+levels+start_frame
    frame_id = frame_id + 1

    levels = levels + 1
  end


  sendProxyDAP(make_response(request,{
        body = {
          stackFrames = stack_frames,
          totalFrames = #stack_frames,
        };
    }))
end

function handlers.stepIn(request)
  step_in = true

  running = true


  sendProxyDAP(make_response(request,{}))

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


  sendProxyDAP(make_response(request, {}))

end

function handlers.threads(request)
  sendProxyDAP(make_response(request, {
        body = {
          threads = {
            {
              id = 1,
              name = "main"
            }
          }
        }
    }))
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

  sendProxyDAP(make_response(request, {
        body = {
          variables = variables,
        }
    }))
end

return handlers
