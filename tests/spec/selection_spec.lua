-- Tests for visual selection functionality in Claude Code
local assert = require('luassert')
local describe = require('plenary.busted').describe
local it = require('plenary.busted').it

describe('selection module', function()
  local claude_code
  local terminal
  local sent_text = nil
  local chan_send_calls = {}

  before_each(function()
    -- Reset tracking variables
    sent_text = nil
    chan_send_calls = {}

    -- Mock vim functions
    _G.vim = _G.vim or {}
    _G.vim.api = _G.vim.api or {}
    _G.vim.fn = _G.vim.fn or {}
    _G.vim.bo = _G.vim.bo or { filetype = 'lua' }
    _G.vim.o = { lines = 100, columns = 100, cmdheight = 1 }
    _G.vim.log = { levels = { WARN = 2, INFO = 1, ERROR = 3 } }

    -- Mock vim.notify
    _G.vim.notify = function(msg, level)
      -- Just capture notifications for testing
    end

    -- Mock vim.defer_fn to execute immediately in tests
    _G.vim.defer_fn = function(fn, delay)
      fn()
    end

    -- Mock vim.schedule
    _G.vim.schedule = function(fn)
      fn()
    end

    -- Mock vim.cmd
    _G.vim.cmd = function(cmd)
      return true
    end

    -- Mock vim.api.nvim_chan_send to track sent text
    _G.vim.api.nvim_chan_send = function(job_id, text)
      table.insert(chan_send_calls, { job_id = job_id, text = text })
      sent_text = text
      return true
    end

    -- Mock vim.api.nvim_buf_is_valid
    _G.vim.api.nvim_buf_is_valid = function(bufnr)
      return bufnr ~= nil and bufnr > 0
    end

    -- Mock vim.api.nvim_get_option_value
    _G.vim.api.nvim_get_option_value = function(option, opts)
      if option == 'buftype' then
        return 'terminal'
      end
      return ''
    end

    -- Mock vim.b for buffer variables
    _G.vim.b = setmetatable({}, {
      __index = function(t, bufnr)
        if not rawget(t, bufnr) then
          rawset(t, bufnr, {
            terminal_job_id = 12345
          })
        end
        return rawget(t, bufnr)
      end
    })

    -- Mock vim.fn.getreg and vim.fn.setreg
    local registers = { v = '' }
    _G.vim.fn.getreg = function(reg)
      return registers[reg] or ''
    end
    _G.vim.fn.setreg = function(reg, value, regtype)
      registers[reg] = value
    end
    _G.vim.fn.getregtype = function(reg)
      return 'v'
    end

    -- Mock vim.fn.expand
    _G.vim.fn.expand = function(pattern)
      if pattern == '%:t' then
        return 'test.lua'
      elseif pattern == '%:p' then
        return '/test/path/test.lua'
      end
      return ''
    end

    -- Mock vim.fn.line
    _G.vim.fn.line = function(pattern)
      if pattern == "'<" then
        return 10
      elseif pattern == "'>" then
        return 20
      end
      return 1
    end

    -- Mock vim.fn.win_findbuf
    _G.vim.fn.win_findbuf = function(bufnr)
      return { 1 } -- Return a window ID
    end

    -- Mock vim.fn.jobwait
    _G.vim.fn.jobwait = function(job_ids, timeout)
      return { -1 } -- -1 means job is still running
    end

    -- Load terminal module
    terminal = require('claude-code.terminal')

    -- Setup claude_code mock
    claude_code = {
      claude_code = {
        instances = { ['global'] = 42 },
        current_instance = 'global',
        saved_updatetime = nil,
      },
      config = {
        window = {
          position = 'botright',
        },
      },
    }
  end)

  describe('terminal.get_job_id', function()
    it('should return job_id when terminal is running', function()
      local job_id = terminal.get_job_id(claude_code)
      assert.are.equal(12345, job_id)
    end)

    it('should return nil when no current instance', function()
      claude_code.claude_code.current_instance = nil
      local job_id = terminal.get_job_id(claude_code)
      assert.is_nil(job_id)
    end)

    it('should return nil when buffer is invalid', function()
      claude_code.claude_code.instances['global'] = -1
      _G.vim.api.nvim_buf_is_valid = function(bufnr)
        return false
      end
      local job_id = terminal.get_job_id(claude_code)
      assert.is_nil(job_id)
    end)
  end)

  describe('terminal.send_text', function()
    it('should send text to terminal', function()
      local result = terminal.send_text(claude_code, 'hello world')
      assert.is_true(result)
      assert.are.equal('hello world', sent_text)
    end)

    it('should return false when terminal is not running', function()
      claude_code.claude_code.current_instance = nil
      local result = terminal.send_text(claude_code, 'hello world')
      assert.is_false(result)
    end)

    it('should use correct job_id', function()
      terminal.send_text(claude_code, 'test message')
      assert.are.equal(1, #chan_send_calls)
      assert.are.equal(12345, chan_send_calls[1].job_id)
      assert.are.equal('test message', chan_send_calls[1].text)
    end)
  end)

  describe('terminal.ensure_visible', function()
    it('should return true when window is already visible', function()
      local result = terminal.ensure_visible(claude_code, claude_code.config)
      assert.is_true(result)
    end)

    it('should return false when no current instance', function()
      claude_code.claude_code.current_instance = nil
      local result = terminal.ensure_visible(claude_code, claude_code.config)
      assert.is_false(result)
    end)

    it('should return false when buffer is invalid', function()
      _G.vim.api.nvim_buf_is_valid = function(bufnr)
        return false
      end
      local result = terminal.ensure_visible(claude_code, claude_code.config)
      assert.is_false(result)
    end)
  end)
end)

describe('init module selection functions', function()
  local init
  local sent_texts = {}

  before_each(function()
    -- Reset tracking
    sent_texts = {}

    -- Setup vim mocks (same as above)
    _G.vim = _G.vim or {}
    _G.vim.api = _G.vim.api or {}
    _G.vim.fn = _G.vim.fn or {}
    _G.vim.bo = { filetype = 'lua' }
    _G.vim.o = { lines = 100, columns = 100, cmdheight = 1, autoread = true }
    _G.vim.log = { levels = { WARN = 2, INFO = 1, ERROR = 3 } }

    _G.vim.notify = function(msg, level) end
    _G.vim.defer_fn = function(fn, delay) fn() end
    _G.vim.schedule = function(fn) fn() end
    _G.vim.cmd = function(cmd) return true end

    _G.vim.api.nvim_chan_send = function(job_id, text)
      table.insert(sent_texts, text)
      return true
    end

    _G.vim.api.nvim_buf_is_valid = function(bufnr)
      return bufnr ~= nil and bufnr > 0
    end

    _G.vim.api.nvim_get_option_value = function(option, opts)
      if option == 'buftype' then
        return 'terminal'
      end
      return ''
    end

    _G.vim.api.nvim_win_close = function(win_id, force)
      return true
    end

    _G.vim.b = setmetatable({}, {
      __index = function(t, bufnr)
        if not rawget(t, bufnr) then
          rawset(t, bufnr, { terminal_job_id = 12345 })
        end
        return rawget(t, bufnr)
      end
    })

    -- Mock registers with selection content
    local registers = { v = 'selected code here' }
    _G.vim.fn.getreg = function(reg)
      return registers[reg] or ''
    end
    _G.vim.fn.setreg = function(reg, value, regtype)
      registers[reg] = value
    end
    _G.vim.fn.getregtype = function(reg)
      return 'v'
    end

    _G.vim.fn.expand = function(pattern)
      if pattern == '%:t' then
        return 'test.lua'
      elseif pattern == '%:p' then
        return '/test/path/test.lua'
      end
      return ''
    end

    _G.vim.fn.line = function(pattern)
      if pattern == "'<" then
        return 10
      elseif pattern == "'>" then
        return 20
      end
      return 1
    end

    _G.vim.fn.win_findbuf = function(bufnr)
      return { 1 }
    end

    _G.vim.fn.jobwait = function(job_ids, timeout)
      return { -1 }
    end

    _G.vim.fn.bufnr = function(pattern)
      return 42
    end

    _G.vim.fn.getcwd = function()
      return '/test/dir'
    end

    _G.vim.fn.shellescape = function(str)
      return "'" .. str .. "'"
    end

    _G.vim.api.nvim_get_current_win = function()
      return 1
    end

    _G.vim.api.nvim_set_option_value = function(option, value, opts)
      return true
    end

    _G.vim.api.nvim_create_augroup = function(name, opts)
      return 1
    end

    _G.vim.api.nvim_create_autocmd = function(events, opts)
      return 1
    end

    _G.vim.api.nvim_set_keymap = function(mode, lhs, rhs, opts)
      return true
    end

    _G.vim.api.nvim_buf_set_keymap = function(buf, mode, lhs, rhs, opts)
      return true
    end

    _G.vim.keymap = {
      set = function(mode, lhs, rhs, opts)
        return true
      end
    }

    _G.vim.tbl_deep_extend = function(behavior, ...)
      local result = {}
      for _, tbl in ipairs({ ... }) do
        if tbl then
          for k, v in pairs(tbl) do
            if type(v) == 'table' and type(result[k]) == 'table' then
              result[k] = _G.vim.tbl_deep_extend(behavior, result[k], v)
            else
              result[k] = v
            end
          end
        end
      end
      return result
    end

    _G.vim.deepcopy = function(tbl)
      if type(tbl) ~= 'table' then
        return tbl
      end
      local copy = {}
      for k, v in pairs(tbl) do
        copy[k] = _G.vim.deepcopy(v)
      end
      return copy
    end

    -- Clear module cache and reload
    package.loaded['claude-code'] = nil
    package.loaded['claude-code.init'] = nil
    package.loaded['claude-code.terminal'] = nil
    package.loaded['claude-code.config'] = nil
    package.loaded['claude-code.commands'] = nil
    package.loaded['claude-code.keymaps'] = nil
    package.loaded['claude-code.file_refresh'] = nil
    package.loaded['claude-code.git'] = nil
    package.loaded['claude-code.version'] = nil

    -- Load init module
    init = require('claude-code')

    -- Setup the plugin
    init.setup({
      keymaps = {
        toggle = {
          normal = false,
          terminal = false,
        },
        selection = {
          ask = false,
        },
        window_navigation = false,
        scrolling = false,
      },
    })

    -- Manually set up instance for testing
    init.claude_code.instances['global'] = 42
    init.claude_code.current_instance = 'global'
  end)

  describe('send function', function()
    it('should send text to terminal', function()
      local result = init.send('hello world')
      assert.is_true(result)
      assert.are.equal(1, #sent_texts)
      assert.are.equal('hello world', sent_texts[1])
    end)
  end)

  describe('open function', function()
    it('should return true when window is visible', function()
      local result = init.open()
      assert.is_true(result)
    end)
  end)

  describe('close function', function()
    it('should close window without error', function()
      local success = pcall(function()
        init.close()
      end)
      assert.is_true(success)
    end)
  end)
end)
