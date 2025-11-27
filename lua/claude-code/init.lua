---@mod claude-code Claude Code Neovim Integration
---@brief [[
--- A plugin for seamless integration between Claude Code AI assistant and Neovim.
--- This plugin provides a terminal-based interface to Claude Code within Neovim.
---
--- Requirements:
--- - Neovim 0.7.0 or later
--- - Claude Code CLI tool installed and available in PATH
--- - plenary.nvim (dependency for git operations)
---
--- Usage:
--- ```lua
--- require('claude-code').setup({
---   -- Configuration options (optional)
--- })
--- ```
---@brief ]]

-- Import modules
local config = require('claude-code.config')
local commands = require('claude-code.commands')
local keymaps = require('claude-code.keymaps')
local file_refresh = require('claude-code.file_refresh')
local terminal = require('claude-code.terminal')
local git = require('claude-code.git')
local version = require('claude-code.version')
local tmux = require('claude-code.tmux')

local M = {}

-- Make imported modules available
M.commands = commands
M.tmux = tmux

-- Store the current configuration
--- @type table
M.config = {}

-- Terminal buffer and window management
--- @type table
M.claude_code = terminal.terminal

--- Force insert mode when entering the Claude Code window
--- This is a public function used in keymaps
function M.force_insert_mode()
  terminal.force_insert_mode(M, M.config)
end

--- Get the current active buffer number
--- @return number|nil bufnr Current Claude instance buffer number or nil
local function get_current_buffer_number()
  -- Get current instance from the instances table
  local current_instance = M.claude_code.current_instance
  if current_instance and type(M.claude_code.instances) == 'table' then
    return M.claude_code.instances[current_instance]
  end
  return nil
end

--- Toggle the Claude Code terminal window
--- This is a public function used by commands
function M.toggle()
  terminal.toggle(M, M.config, git)

  -- Set up terminal navigation keymaps after toggling
  local bufnr = get_current_buffer_number()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    keymaps.setup_terminal_navigation(M, M.config)
  end
end

--- Toggle the Claude Code terminal window with a specific command variant
--- @param variant_name string The name of the command variant to use
function M.toggle_with_variant(variant_name)
  if not variant_name or not M.config.command_variants[variant_name] then
    -- If variant doesn't exist, fall back to regular toggle
    return M.toggle()
  end

  -- Store the original command
  local original_command = M.config.command

  -- Set the command with the variant args
  M.config.command = original_command .. ' ' .. M.config.command_variants[variant_name]

  -- Call the toggle function with the modified command
  terminal.toggle(M, M.config, git)

  -- Set up terminal navigation keymaps after toggling
  local bufnr = get_current_buffer_number()
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    keymaps.setup_terminal_navigation(M, M.config)
  end

  -- Restore the original command
  M.config.command = original_command
end

--- Get the current version of the plugin
--- @return string version Current version string
function M.get_version()
  return version.string()
end

--- Version information
M.version = version

--- Send raw text to the Claude Code terminal or tmux pane
--- @param text string Text to send to the terminal
--- @return boolean success True if text was sent successfully
function M.send(text)
  -- Check tmux first if enabled
  if M.config.tmux and M.config.tmux.enable then
    local tmux_pane = tmux.find_claude_pane()
    if tmux_pane then
      -- If prefer_tmux is true, or nvim terminal is not running, use tmux
      if M.config.tmux.prefer_tmux or not M.claude_code.current_instance then
        return tmux.send_text(tmux_pane, text)
      end
    end
  end

  -- Fall back to nvim terminal
  -- Ensure Claude Code is running
  if not M.claude_code.current_instance then
    -- Start Claude Code first
    M.toggle()
    -- Wait a bit for terminal to initialize
    vim.defer_fn(function()
      terminal.send_text(M, text)
    end, 100)
    return true
  end

  return terminal.send_text(M, text)
end

--- Send raw text followed by Enter to the Claude Code terminal or tmux pane
--- @param text string Text to send
--- @return boolean success True if text was sent successfully
function M.send_with_enter(text)
  -- Check tmux first if enabled
  if M.config.tmux and M.config.tmux.enable then
    local tmux_pane = tmux.find_claude_pane()
    if tmux_pane then
      if M.config.tmux.prefer_tmux or not M.claude_code.current_instance then
        return tmux.send_text_with_enter(tmux_pane, text)
      end
    end
  end

  -- Fall back to nvim terminal
  if not M.send(text) then
    return false
  end
  return M.send('\r')
end

--- Check if Claude Code is available (either in tmux or nvim terminal)
--- @return boolean available True if Claude Code is available
--- @return string source "tmux" or "nvim" indicating where Claude Code is running
function M.is_available()
  -- Check tmux first if enabled
  if M.config.tmux and M.config.tmux.enable then
    if tmux.find_claude_pane() then
      return true, 'tmux'
    end
  end

  -- Check nvim terminal
  if M.claude_code.current_instance then
    local bufnr = M.claude_code.instances[M.claude_code.current_instance]
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      return true, 'nvim'
    end
  end

  return false, nil
end

--- Open Claude Code and focus the terminal window
--- @return boolean success True if window is now visible
function M.open()
  if not M.claude_code.current_instance then
    M.toggle()
    return true
  end

  return terminal.ensure_visible(M, M.config)
end

--- Close the Claude Code terminal window (hide, not terminate)
function M.close()
  local instance_id = M.claude_code.current_instance
  if not instance_id then
    return
  end

  local bufnr = M.claude_code.instances[instance_id]
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local win_ids = vim.fn.win_findbuf(bufnr)
  for _, win_id in ipairs(win_ids) do
    vim.api.nvim_win_close(win_id, true)
  end
end

--- Setup function for the plugin
--- @param user_config? table User configuration table (optional)
function M.setup(user_config)
  -- Parse and validate configuration
  -- Don't use silent mode for regular usage - users should see config errors
  M.config = config.parse_config(user_config, false)

  -- Set up autoread option
  vim.o.autoread = true

  -- Set up file refresh functionality
  file_refresh.setup(M, M.config)

  -- Register commands
  commands.register_commands(M)

  -- Register keymaps
  keymaps.register_keymaps(M, M.config)
end

return M
