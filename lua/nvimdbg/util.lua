local M = {}

function M.get_uri_path(path)
  local res = vim.fn.fnamemodify(path, ':p')
  res = vim.fn.resolve(res)

  return vim.uri_from_fname(res:lower())
end

return M
