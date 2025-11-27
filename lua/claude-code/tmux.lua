---@mod claude-code.tmux Tmux integration for claude-code.nvim
---@brief [[
--- This module provides tmux integration for claude-code.nvim.
--- It allows sending text to Claude Code running in a separate tmux pane/window.
---@brief ]]

local M = {}

--- Check if we're running inside tmux
--- @return boolean is_tmux True if running inside tmux
function M.is_in_tmux()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ''
end

--- Get child PIDs of a process using ps (more reliable on macOS than pgrep -P)
--- @param pid string Parent process ID
--- @return table children List of child PIDs
local function get_child_pids(pid)
  local children = {}
  -- Use ps to find all processes and filter by PPID
  local result = vim.fn.system(string.format("ps -eo pid,ppid,comm 2>/dev/null | awk '$2 == %s {print $1}'", pid))
  for child_pid in result:gmatch('%d+') do
    table.insert(children, child_pid)
  end
  return children
end

--- Check if a process or its descendants include claude
--- @param pid string Process ID to check
--- @return boolean found True if claude is found
local function has_claude_descendant(pid)
  -- Check direct children first
  local children = get_child_pids(pid)
  if #children == 0 then
    return false
  end

  for _, child_pid in ipairs(children) do
    -- Check if this child is claude
    local proc_name = vim.fn.system(string.format("ps -p %s -o comm= 2>/dev/null", child_pid))
    proc_name = vim.trim(proc_name)
    if proc_name == 'claude' then
      return true
    end

    -- Check grandchildren
    local grandchildren = get_child_pids(child_pid)
    for _, gc_pid in ipairs(grandchildren) do
      local gc_name = vim.fn.system(string.format("ps -p %s -o comm= 2>/dev/null", gc_pid))
      gc_name = vim.trim(gc_name)
      if gc_name == 'claude' then
        return true
      end
    end
  end

  return false
end

--- Find a tmux pane running Claude Code
--- @return string|nil pane_id The pane ID if found, nil otherwise
function M.find_claude_pane()
  if not M.is_in_tmux() then
    return nil
  end

  -- Get current pane to exclude it
  local current_pane = M.get_current_pane()

  -- First, try to find claude in the same session (not just window)
  -- Using -s flag to search current session only
  local result = vim.fn.system("tmux list-panes -s -F '#{pane_id}:#{pane_pid}'")
  if vim.v.shell_error ~= 0 then
    return nil
  end

  for line in result:gmatch('[^\r\n]+') do
    local pane_id, pid = line:match('^(%%?%d+):(%d+)')
    if pane_id and pid and pane_id ~= current_pane then
      if has_claude_descendant(pid) then
        return pane_id
      end
    end
  end

  -- Fallback: search all panes across all sessions
  result = vim.fn.system("tmux list-panes -a -F '#{pane_id}:#{pane_pid}'")
  if vim.v.shell_error ~= 0 then
    return nil
  end

  for line in result:gmatch('[^\r\n]+') do
    local pane_id, pid = line:match('^(%%?%d+):(%d+)')
    if pane_id and pid and pane_id ~= current_pane then
      if has_claude_descendant(pid) then
        return pane_id
      end
    end
  end

  return nil
end

--- Send text to a tmux pane
--- @param pane_id string The target pane ID
--- @param text string The text to send
--- @return boolean success True if send was successful
function M.send_text(pane_id, text)
  if not pane_id then
    return false
  end

  -- Use send-keys with literal flag to handle special characters
  -- We escape the text and send it
  local escaped_text = vim.fn.shellescape(text)
  local cmd = string.format("tmux send-keys -t %s -l %s", pane_id, escaped_text)
  vim.fn.system(cmd)

  return vim.v.shell_error == 0
end

--- Send text followed by Enter to a tmux pane
--- @param pane_id string The target pane ID
--- @param text string The text to send
--- @return boolean success True if send was successful
function M.send_text_with_enter(pane_id, text)
  if not M.send_text(pane_id, text) then
    return false
  end

  -- Send Enter key
  vim.fn.system(string.format("tmux send-keys -t %s Enter", pane_id))
  return vim.v.shell_error == 0
end

--- Focus the tmux pane containing Claude Code
--- @param pane_id string The target pane ID
--- @return boolean success True if focus was successful
function M.focus_pane(pane_id)
  if not pane_id then
    return false
  end

  vim.fn.system(string.format("tmux select-pane -t %s", pane_id))
  return vim.v.shell_error == 0
end

--- Get the current tmux pane ID (the one running nvim)
--- @return string|nil pane_id The current pane ID
function M.get_current_pane()
  if not M.is_in_tmux() then
    return nil
  end

  local result = vim.fn.system("tmux display-message -p '#{pane_id}'")
  if vim.v.shell_error ~= 0 then
    return nil
  end

  return vim.trim(result)
end

--- Check if Claude Code is available in tmux (cached check)
--- @return boolean available True if Claude Code pane exists in tmux
function M.is_claude_available()
  return M.find_claude_pane() ~= nil
end

return M
