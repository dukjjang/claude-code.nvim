---@mod claude-code.keymaps Keymap management for claude-code.nvim
---@brief [[
--- This module provides keymap registration and handling for claude-code.nvim.
--- It handles normal mode, terminal mode, and window navigation keymaps.
---@brief ]]

local M = {}

--- Register keymaps for claude-code.nvim
--- @param claude_code table The main plugin module
--- @param config table The plugin configuration
function M.register_keymaps(claude_code, config)
  local map_opts = { noremap = true, silent = true }

  -- Normal mode toggle keymaps
  if config.keymaps.toggle.normal then
    vim.api.nvim_set_keymap(
      'n',
      config.keymaps.toggle.normal,
      [[<cmd>ClaudeCode<CR>]],
      vim.tbl_extend('force', map_opts, { desc = 'Claude Code: Toggle' })
    )
  end

  if config.keymaps.toggle.terminal then
    -- Terminal mode toggle keymap
    -- In terminal mode, special keys like Ctrl need different handling
    -- We use a direct escape sequence approach for more reliable terminal mappings
    vim.api.nvim_set_keymap(
      't',
      config.keymaps.toggle.terminal,
      [[<C-\><C-n>:ClaudeCode<CR>]],
      vim.tbl_extend('force', map_opts, { desc = 'Claude Code: Toggle' })
    )
  end

  -- Register variant keymaps if configured
  if config.keymaps.toggle.variants then
    for variant_name, keymap in pairs(config.keymaps.toggle.variants) do
      if keymap then
        -- Convert variant name to PascalCase for command name (e.g., "continue" -> "Continue")
        local capitalized_name = variant_name:gsub('^%l', string.upper)
        local cmd_name = 'ClaudeCode' .. capitalized_name

        vim.api.nvim_set_keymap(
          'n',
          keymap,
          string.format([[<cmd>%s<CR>]], cmd_name),
          vim.tbl_extend('force', map_opts, { desc = 'Claude Code: ' .. capitalized_name })
        )
      end
    end
  end

  -- Visual mode keymaps for selection
  if config.keymaps.selection and config.keymaps.selection.ask then
    --- Wait for Claude Code CLI to be ready by monitoring terminal buffer content
    --- @param bufnr number Terminal buffer number
    --- @param callback function Function to call when CLI is ready
    --- @param is_new_session boolean Whether this is a new session
    local function wait_for_cli_ready(bufnr, callback, is_new_session)
      -- For existing sessions, CLI is already ready - execute immediately
      if not is_new_session then
        callback()
        return
      end

      local max_attempts = 50 -- 50 * 50ms = 2.5 seconds max
      local attempts = 0

      local function check_ready()
        attempts = attempts + 1

        if not vim.api.nvim_buf_is_valid(bufnr) then
          if attempts < max_attempts then
            vim.defer_fn(check_ready, 50)
          else
            vim.notify('Claude Code: Terminal buffer became invalid', vim.log.levels.ERROR)
          end
          return
        end

        -- Get terminal buffer content (last few lines where prompt would appear)
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        local start_line = math.max(0, line_count - 5)
        local lines = vim.api.nvim_buf_get_lines(bufnr, start_line, line_count, false)
        local content = table.concat(lines, '\n')

        -- Claude Code CLI shows ">" prompt when ready for input
        if content:match('>%s*$') then
          callback()
          return
        end

        if attempts < max_attempts then
          vim.defer_fn(check_ready, 50)
        else
          -- Fallback: send anyway after timeout
          callback()
        end
      end

      -- Start checking immediately
      check_ready()
    end

    vim.keymap.set('x', config.keymaps.selection.ask, function()
        -- Capture file info BEFORE vim.ui.input (which exits visual mode)
        local filepath = vim.fn.expand('%:p')

        -- Check for unsaved buffer
        if filepath == '' then
          vim.notify('Claude Code: Cannot send selection from unsaved buffer', vim.log.levels.WARN)
          return
        end

        -- Use visual mode marks (current selection)
        local start_line = vim.fn.line('v')
        local end_line = vim.fn.line('.')
        -- Ensure start <= end
        if start_line > end_line then
          start_line, end_line = end_line, start_line
        end

        vim.ui.input({ prompt = 'Ask Claude: ' }, function(input)
          if input and input ~= '' then
            -- Just send file path and line range - Claude Code can read the file
            local message = string.format(
              'See %s:%d-%d\n\n%s',
              filepath,
              start_line,
              end_line,
              input
            )
            local claude = require('claude-code')
            local tmux_mod = require('claude-code.tmux')

            -- Check if we should use tmux
            local use_tmux = false
            local tmux_pane = nil
            if claude.config.tmux and claude.config.tmux.enable then
              tmux_pane = tmux_mod.find_claude_pane()
              if tmux_pane then
                if claude.config.tmux.prefer_tmux or not claude.claude_code.current_instance then
                  use_tmux = true
                end
              end
            end

            if use_tmux and tmux_pane then
              -- Send directly to tmux pane
              local sent = tmux_mod.send_text(tmux_pane, message)
              if sent then
                vim.defer_fn(function()
                  tmux_mod.send_text(tmux_pane, '\r')
                end, 50)
              end
            else
              -- Use nvim terminal flow
              -- Check if Claude Code is already running
              local is_new_session = not claude.claude_code.current_instance
                or not claude.claude_code.instances[claude.claude_code.current_instance]

              claude.open()

              -- Get buffer number after open
              local instance_id = claude.claude_code.current_instance
              local bufnr = instance_id and claude.claude_code.instances[instance_id]

              if not bufnr then
                vim.notify('Claude Code: Failed to get terminal buffer', vim.log.levels.ERROR)
                return
              end

              -- Wait for CLI to be ready, then send message
              wait_for_cli_ready(bufnr, function()
                local sent = claude.send(message)
                if sent then
                  vim.defer_fn(function()
                    claude.send('\r')
                  end, 50)
                end
              end, is_new_session)
            end
          end
        end)
      end, { noremap = true, silent = true, desc = 'Claude Code: Ask about selection' })
  end

  -- Register with which-key if it's available
  vim.defer_fn(function()
    local status_ok, which_key = pcall(require, 'which-key')
    if status_ok then
      if config.keymaps.toggle.normal then
        which_key.add {
          mode = 'n',
          { config.keymaps.toggle.normal, desc = 'Claude Code: Toggle', icon = '🤖' },
        }
      end
      if config.keymaps.toggle.terminal then
        which_key.add {
          mode = 't',
          { config.keymaps.toggle.terminal, desc = 'Claude Code: Toggle', icon = '🤖' },
        }
      end

      -- Register variant keymaps with which-key
      if config.keymaps.toggle.variants then
        for variant_name, keymap in pairs(config.keymaps.toggle.variants) do
          if keymap then
            local capitalized_name = variant_name:gsub('^%l', string.upper)
            which_key.add {
              mode = 'n',
              { keymap, desc = 'Claude Code: ' .. capitalized_name, icon = '🤖' },
            }
          end
        end
      end

      -- Register selection keymaps with which-key
      if config.keymaps.selection and config.keymaps.selection.ask then
        which_key.add {
          mode = 'x',
          { config.keymaps.selection.ask, desc = 'Claude Code: Ask about selection', icon = '🤖' },
        }
      end
    end
  end, 100)
end

--- Set up terminal-specific keymaps for window navigation
--- @param claude_code table The main plugin module
--- @param config table The plugin configuration
function M.setup_terminal_navigation(claude_code, config)
  -- Get current active Claude instance buffer
  local current_instance = claude_code.claude_code.current_instance
  local buf = current_instance and claude_code.claude_code.instances[current_instance]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    -- Create autocommand to enter insert mode when the terminal window gets focus
    local augroup = vim.api.nvim_create_augroup('ClaudeCodeTerminalFocus_' .. buf, { clear = true })

    -- Set up multiple events for more reliable focus detection
    vim.api.nvim_create_autocmd(
      { 'WinEnter', 'BufEnter', 'WinLeave', 'FocusGained', 'CmdLineLeave' },
      {
        group = augroup,
        callback = function()
          vim.schedule(claude_code.force_insert_mode)
        end,
        desc = 'Auto-enter insert mode when focusing Claude Code terminal',
      }
    )

    -- Window navigation keymaps
    if config.keymaps.window_navigation then
      -- Window navigation keymaps with special handling to force insert mode in the target window
      vim.api.nvim_buf_set_keymap(
        buf,
        't',
        '<C-h>',
        [[<C-\><C-n><C-w>h:lua require("claude-code").force_insert_mode()<CR>]],
        { noremap = true, silent = true, desc = 'Window: move left' }
      )
      vim.api.nvim_buf_set_keymap(
        buf,
        't',
        '<C-j>',
        [[<C-\><C-n><C-w>j:lua require("claude-code").force_insert_mode()<CR>]],
        { noremap = true, silent = true, desc = 'Window: move down' }
      )
      vim.api.nvim_buf_set_keymap(
        buf,
        't',
        '<C-k>',
        [[<C-\><C-n><C-w>k:lua require("claude-code").force_insert_mode()<CR>]],
        { noremap = true, silent = true, desc = 'Window: move up' }
      )
      vim.api.nvim_buf_set_keymap(
        buf,
        't',
        '<C-l>',
        [[<C-\><C-n><C-w>l:lua require("claude-code").force_insert_mode()<CR>]],
        { noremap = true, silent = true, desc = 'Window: move right' }
      )

      -- Also add normal mode mappings for when user is in normal mode in the terminal
      vim.api.nvim_buf_set_keymap(
        buf,
        'n',
        '<C-h>',
        [[<C-w>h:lua require("claude-code").force_insert_mode()<CR>]],
        { noremap = true, silent = true, desc = 'Window: move left' }
      )
      vim.api.nvim_buf_set_keymap(
        buf,
        'n',
        '<C-j>',
        [[<C-w>j:lua require("claude-code").force_insert_mode()<CR>]],
        { noremap = true, silent = true, desc = 'Window: move down' }
      )
      vim.api.nvim_buf_set_keymap(
        buf,
        'n',
        '<C-k>',
        [[<C-w>k:lua require("claude-code").force_insert_mode()<CR>]],
        { noremap = true, silent = true, desc = 'Window: move up' }
      )
      vim.api.nvim_buf_set_keymap(
        buf,
        'n',
        '<C-l>',
        [[<C-w>l:lua require("claude-code").force_insert_mode()<CR>]],
        { noremap = true, silent = true, desc = 'Window: move right' }
      )
    end

    -- Add scrolling keymaps
    if config.keymaps.scrolling then
      vim.api.nvim_buf_set_keymap(
        buf,
        't',
        '<C-f>',
        [[<C-\><C-n><C-f>i]],
        { noremap = true, silent = true, desc = 'Scroll full page down' }
      )
      vim.api.nvim_buf_set_keymap(
        buf,
        't',
        '<C-b>',
        [[<C-\><C-n><C-b>i]],
        { noremap = true, silent = true, desc = 'Scroll full page up' }
      )
    end
  end
end

return M
