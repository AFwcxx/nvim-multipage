-- lua/multipage/init.lua
local M = {}

---------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------

local api = vim.api

local DEFAULTS = {
  -- number of lines of overlap between panes
  -- e.g. overlap = 1 => page_span = height - 1
  overlap = 1,
}

M.config = vim.deepcopy(DEFAULTS)

local function get_tabpage_windows_for_buf(tabpage, bufnr)
  local wins = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(tabpage)) do
    if api.nvim_win_get_buf(win) == bufnr then
      table.insert(wins, win)
    end
  end
  -- sort left-to-right by column position
  table.sort(wins, function(a, b)
    local _, col_a = unpack(api.nvim_win_get_position(a))
    local _, col_b = unpack(api.nvim_win_get_position(b))
    return col_a < col_b
  end)
  return wins
end

local function clamp(x, min, max)
  if x < min then return min end
  if x > max then return max end
  return x
end

---------------------------------------------------------------------
-- Core layout logic
---------------------------------------------------------------------

-- Apply multi-page layout for a given buffer in a given tabpage.
-- Does NOT create new splits; only arranges existing windows and
-- ensures scrollbind is set correctly.
function M.apply_layout_for(bufnr, tabpage)
  local wins = get_tabpage_windows_for_buf(tabpage, bufnr)
  if #wins == 0 then
    return
  end

  -- Only one window for this buffer: still keep scrollbind if enabled,
  -- but nothing special to do layout-wise.
  if #wins == 1 then
    local win = wins[1]
    api.nvim_win_call(win, function()
      vim.wo.scrollbind = true
    end)
    return
  end

  local left_win = wins[1]
  local lastline = api.nvim_buf_line_count(bufnr)

  -- Use full window height of the left-most window
  local height = api.nvim_win_get_height(left_win)
  if height <= 0 then
    return
  end

  -- We want configurable overlap between panes:
  -- overlap = 1:
  --   left  : [T ... T+H-1]
  --   right : [T+H-1 ... T+2H-2]
  --
  -- overlap = 2:
  --   left  : [T ... T+H-1]
  --   right : [T+H-2 ... T+2H-3]
  local overlap = (M.config and M.config.overlap) or 1
  local page_span = math.max(1, height - overlap)

  -- Capture base view (topline) from left-most window
  local current_win = api.nvim_get_current_win()
  api.nvim_set_current_win(left_win)
  local base_view = vim.fn.winsaveview()
  api.nvim_set_current_win(current_win)

  -- Ensure scrollbind is enabled only for windows of this buffer
  for _, win in ipairs(wins) do
    api.nvim_win_call(win, function()
      vim.wo.scrollbind = true
    end)
  end

  -- Layout each window with increasing topline offset based on page_span
  for idx, win in ipairs(wins) do
    api.nvim_win_call(win, function()
      local v = vim.fn.winsaveview()
      local desired_top = base_view.topline + page_span * (idx - 1)

      -- Clamp topline so we don't scroll past the end
      local max_top = math.max(1, lastline - height + 1)
      v.topline = clamp(desired_top, 1, max_top)

      vim.fn.winrestview(v)
    end)
  end
end

---------------------------------------------------------------------
-- Creating extra splits when enabling
---------------------------------------------------------------------

local function ensure_columns_for(bufnr, tabpage, columns)
  local wins = get_tabpage_windows_for_buf(tabpage, bufnr)

  if not columns or columns <= #wins then
    return wins
  end

  local current_win = api.nvim_get_current_win()

  -- Use current window if it has the buffer, else use the left-most existing
  local base_win = current_win
  if api.nvim_win_get_buf(base_win) ~= bufnr and #wins > 0 then
    base_win = wins[#wins]
  end

  -- Create extra vertical splits until we reach desired columns
  for _ = #wins + 1, columns do
    api.nvim_set_current_win(base_win)
    vim.cmd('vsplit')
    local new_win = api.nvim_get_current_win()
    api.nvim_win_set_buf(new_win, bufnr)
    table.insert(wins, new_win)
    base_win = new_win
  end

  api.nvim_set_current_win(current_win)
  return get_tabpage_windows_for_buf(tabpage, bufnr)
end

---------------------------------------------------------------------
-- Public API: enable/disable/toggle per buffer
---------------------------------------------------------------------

function M.enable(columns)
  local bufnr = api.nvim_get_current_buf()
  local tabpage = api.nvim_get_current_tabpage()

  -- Mark this buffer as using multipage
  vim.b[bufnr].multipage_enabled = true

  -- Optional: ensure we have N columns for this buffer in this tab
  if columns and columns > 0 then
    ensure_columns_for(bufnr, tabpage, columns)
  end

  -- Apply layout for this buffer in this tab
  M.apply_layout_for(bufnr, tabpage)
end

function M.disable()
  local bufnr = api.nvim_get_current_buf()
  local tabpage = api.nvim_get_current_tabpage()

  vim.b[bufnr].multipage_enabled = false

  -- Turn off scrollbind in all windows of this buffer in this tab
  local wins = get_tabpage_windows_for_buf(tabpage, bufnr)
  for _, win in ipairs(wins) do
    api.nvim_win_call(win, function()
      vim.wo.scrollbind = false
      -- You could also turn off cursorbind if you enable it elsewhere:
      -- vim.wo.cursorbind = false
    end)
  end
end

function M.toggle(columns)
  local bufnr = api.nvim_get_current_buf()
  if vim.b[bufnr].multipage_enabled then
    M.disable()
  else
    M.enable(columns)
  end
end

---------------------------------------------------------------------
-- Autocmds & user commands
---------------------------------------------------------------------

function M.setup(opts)
  opts = opts or {}
  M.config = vim.tbl_extend('force', M.config, opts)

  local group = api.nvim_create_augroup('MultipageLayout', { clear = true })

  -------------------------------------------------------------------
  -- existing autocmds...
  -------------------------------------------------------------------
  api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    callback = function(args)
      local bufnr = args.buf
      if not (bufnr and api.nvim_buf_is_valid(bufnr)) then
        return
      end

      local win = args.win or api.nvim_get_current_win()
      if not (win and api.nvim_win_is_valid(win)) then
        return
      end
      local tabpage = api.nvim_win_get_tabpage(win)

      if vim.b[bufnr].multipage_enabled then
        M.apply_layout_for(bufnr, tabpage)
      else
        api.nvim_win_call(win, function()
          vim.wo.scrollbind = false
        end)
      end
    end,
  })

  api.nvim_create_autocmd('WinEnter', {
    group = group,
    callback = function(args)
      local win = args.win or api.nvim_get_current_win()
      if not (win and api.nvim_win_is_valid(win)) then
        return
      end

      local bufnr = api.nvim_win_get_buf(win)
      if not (bufnr and api.nvim_buf_is_valid(bufnr)) then
        return
      end
      local tabpage = api.nvim_win_get_tabpage(win)

      if vim.b[bufnr].multipage_enabled then
        M.apply_layout_for(bufnr, tabpage)
      else
        api.nvim_win_call(win, function()
          vim.wo.scrollbind = false
        end)
      end
    end,
  })

  -------------------------------------------------------------------
  -- existing user commands...
  -------------------------------------------------------------------
  api.nvim_create_user_command('MultipageEnable', function(opts)
    local n = nil
    if opts.args ~= '' then
      n = tonumber(opts.args)
    elseif opts.count and opts.count > 0 then
      n = opts.count
    end
    M.enable(n)
  end, { nargs = '?', count = 0 })

  api.nvim_create_user_command('MultipageDisable', function(_)
    M.disable()
  end, {})

  api.nvim_create_user_command('MultipageToggle', function(opts)
    local n = nil
    if opts.args ~= '' then
      n = tonumber(opts.args)
    elseif opts.count and opts.count > 0 then
      n = opts.count
    end
    M.toggle(n)
  end, { nargs = '?', count = 0 })

  -------------------------------------------------------------------
  -- nvim-treesitter-context integration: left-most window only
  -------------------------------------------------------------------
  local ok, ts_context = pcall(require, 'treesitter-context')
  if ok and not M._ts_context_wrapped then
    M._ts_context_wrapped = true

    local orig_update = ts_context.update

    ts_context.update = function(...)
      local win = api.nvim_get_current_win()
      local bufnr = api.nvim_get_current_buf()

      -- Only intervene for buffers using multipage
      if vim.b[bufnr].multipage_enabled then
        local tabpage = api.nvim_get_current_tabpage()
        local wins = get_tabpage_windows_for_buf(tabpage, bufnr)

        if #wins > 0 then
          local left_win = wins[1]
          if api.nvim_win_is_valid(left_win) then
            -- Run treesitter-context update as if we were in the left-most window
            api.nvim_set_current_win(left_win)
            local ok2, res = pcall(orig_update, ...)
            api.nvim_set_current_win(win)
            if ok2 then
              return res
            end
            -- if it errored, just fall through to original below
          end
        end
      end

      -- Non-multipage buffers, or fallback
      return orig_update(...)
    end
  end
end


return M

