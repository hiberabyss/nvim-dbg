local M = {}

local seq_id = 1

function M.make_response(request, response)
  local msg = {
    type = "response",
    seq = seq_id,
    request_seq = request.seq,
    success = true,
    command = request.command
  }
  seq_id = seq_id + 1
  return vim.tbl_extend('error', msg, response)
end

function M.make_event(event, body)
  local msg = {
    type = "event",
    seq = seq_id,
    event = event,
  }

  if body then
    msg.body = body
  end

  seq_id = seq_id + 1
  return msg
end

function M.reset_seqid()
  seq_id = 1
end

function M.is_initialize(request)
  if not request or request.command ~= 'initialize' then
    return false
  end

  return true
end

return M
