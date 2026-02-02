-- dslua/cli/repl.lua
-- Interactive REPL for exploring dslua programs

local M = {}

-- =============================================================================
-- REPL Configuration
-- =============================================================================

M.REPLConfig = {}
M.REPLConfig.__index = M.REPLConfig

function M.REPLConfig.new(opts)
  opts = opts or {}

  local self = {
    -- Prompt configuration
    prompt = opts.prompt or "dslua> ",
    continuation_prompt = opts.continuation_prompt or "... ",

    -- History
    history_file = opts.history_file or "/tmp/dslua_repl_history.txt",
    history_size = opts.history_size or 1000,

    -- Context
    context = opts.context or {},

    -- Built-ins
    builtins = opts.builtins or {}
  }

  setmetatable(self, M.REPLConfig)
  return self
end

-- =============================================================================
-- REPL Engine
-- =============================================================================

M.REPL = {}
M.REPL.__index = M.REPL

function M.REPL.new(opts)
  opts = opts or {}

  local self = {
    config = M.REPLConfig.new(opts),
    running = false,
    history = {},
    multiline_buffer = {}
  }

  setmetatable(self, M.REPL)

  -- Load history if file exists
  self:_load_history()

  -- Set up built-ins
  self:_setup_builtins()

  return self
end

-- Start REPL loop
function M.REPL:start()
  self.running = true

  print([[

    ╔═══════════════════════════════════════════════════════════════╗
    ║                  dslua Interactive REPL                      ║
    ║              DSPy Framework for LuaJIT                        ║
    ╠═══════════════════════════════════════════════════════════════╣
    ║  Type 'help' for available commands                         ║
    ║  Type 'quit' or 'exit' to leave                              ║
    ╚═══════════════════════════════════════════════════════════════╝
  ]])

  while self.running do
    local prompt = #self.multiline_buffer > 0 and
      self.config.continuation_prompt or
      self.config.prompt

    io.write(prompt)
    io.flush()

    local input = io.read()

    if not input then
      -- EOF (Ctrl+D)
      print()
      break
    end

    -- Skip empty lines in multiline mode
    if #input == 0 and #self.multiline_buffer == 0 then
      goto continue
    end

    -- Add to buffer
    table.insert(self.multiline_buffer, input)

    -- Check if input is complete
    if self:_is_complete_input() then
      local full_input = table.concat(self.multiline_buffer, "\n")
      self.multiline_buffer = {}

      -- Save to history
      self:_add_to_history(full_input)

      -- Execute
      local ok, result = pcall(function()
        return self:_execute(full_input)
      end)

      if not ok then
        print("Error: " .. tostring(result))
      elseif result ~= nil then
        print(self:_format_result(result))
      end
    end

    ::continue::
  end

  print("\nGoodbye!")
end

-- Execute input
function M.REPL:_execute(input)
  local trimmed = input:match("^%s*(.-)%s*$")

  -- Check for special commands
  if trimmed:match("^%.") or trimmed:match("^:") then
    return self:_execute_command(trimmed)
  end

  -- Check for expression
  local expr = trimmed:match("^%s*=%s*(.+)")
  if expr then
    return self:_evaluate_expression(expr)
  end

  -- Execute as Lua code
  return self:_execute_lua(trimmed)
end

-- Execute special command
function M.REPL:_execute_command(cmd)
  local parts = {}
  for part in cmd:gmatch("%S+") do
    table.insert(parts, part)
  end

  local command = parts[1]:gsub("^[:%.,]", "")
  local args = {table.unpack(parts, 2)}

  -- Built-in commands
  if command == "help" or command == "h" then
    return self:_cmd_help(args)
  elseif command == "quit" or command == "exit" or command == "q" then
    self.running = false
    return "Exiting..."
  elseif command == "clear" or command == "c" then
    os.execute("clear")
    return ""
  elseif command == "vars" or command == "v" then
    return self:_cmd_vars(args)
  elseif command == "history" or command == "hist" then
    return self:_cmd_history(args)
  elseif command == "load" or command == "l" then
    return self:_cmd_load(args)
  elseif command == "save" or command == "s" then
    return self:_cmd_save(args)
  elseif command == "reset" or command == "r" then
    return self:_cmd_reset(args)
  else
    return nil, "Unknown command: " .. command
  end
end

-- Evaluate expression
function M.REPL:_evaluate_expression(expr)
  -- Create function with context
  local context_str = self:_context_to_string()
  local fn, err = load("return " .. expr, "expr", "t", self.config.context)

  if not fn then
    return nil, "Syntax error: " .. err
  end

  local ok, result = pcall(fn)
  if not ok then
    return nil, "Runtime error: " .. result
  end

  return result
end

-- Execute Lua code
function M.REPL:_execute_lua(code)
  local fn, err = load(code, "repl", "t", self.config.context)

  if not fn then
    return nil, "Syntax error: " .. err
  end

  local ok, result = pcall(fn)
  if not ok then
    return nil, "Runtime error: " .. result
  end

  return result
end

-- Check if input is complete
function M.REPL:_is_complete_input()
  local input = table.concat(self.multiline_buffer, "\n")

  -- Check for incomplete blocks
  local open_brackets = select(2, input:gsub("%(", ""))
  local close_brackets = select(2, input:gsub("%)", ""))
  local open_braces = select(2, input:gsub("%{", ""))
  local close_braces = select(2, input:gsub("%}", ""))
  local open_brackets2 = select(2, input:gsub("%[", ""))
  local close_brackets2 = select(2, input:gsub("%]", ""))

  if open_brackets > close_brackets or
     open_braces > close_braces or
     open_brackets2 > close_brackets2 then
    return false
  end

  -- Check for incomplete keywords
  if input:match("%f[%w_][fF][uU][nN][cC][tT][iI][oO][nN]%s*$") or
     input:match("%f[%w_][iI][fF]%s*$") or
     input:match("%f[%w_][fF][oO][rR]%s*$") or
     input:match("%f[%w_][wW][hH][iI][lL][eE]%s*$") or
     input:match("%f[%w_][rR][eE][pP][eE][aA][tT]%s*$") or
     input:match("%f[%w_][lL][oO][cC][aA][lL]%s*$") then
    return false
  end

  return true
end

-- =============================================================================
-- Commands
-- =============================================================================

function M.REPL:_cmd_help(args)
  local help_text = [[

Available Commands:

  General:
    .help, .h              Show this help message
    .quit, .exit, .q       Exit the REPL
    .clear, .c             Clear the screen

  Context:
    .vars, .v              List all variables in context
    .reset, .r             Reset context (clear all variables)

  History:
    .history, .hist        Show command history
    .history N             Show last N commands

  Files:
    .load FILE [VAR]       Load Lua file into context (optional variable name)
    .save FILE [EXPR]      Save expression result to file

  Evaluation:
    =expr                  Evaluate expression and show result
    code                   Execute Lua code

Examples:
    =1 + 2                 -- Evaluate expression (outputs: 3)
    x = 10                 -- Set variable
    =x * 2                 -- Use variable (outputs: 20)
    .vars                  -- List variables
    .load example.lua      -- Load file
    print("hello")         -- Execute code
]]
  return help_text
end

function M.REPL:_cmd_vars(args)
  local vars = {}
  for k, v in pairs(self.config.context) do
    local value_str = self:_format_value(v)
    table.insert(vars, string.format("  %s = %s", k, value_str))
  end

  if #vars == 0 then
    return "No variables defined."
  end

  table.sort(vars)
  return "Variables:\n" .. table.concat(vars, "\n")
end

function M.REPL:_cmd_history(args)
  local n = tonumber(args[1]) or 10
  n = math.min(n, #self.history)

  if n == 0 then
    return "No history yet."
  end

  local lines = {"History (last " .. n .. " commands):"}
  for i = #self.history - n + 1, #self.history do
    table.insert(lines, string.format("  %d: %s", i, self.history[i]))
  end

  return table.concat(lines, "\n")
end

function M.REPL:_cmd_load(args)
  if #args == 0 then
    return nil, "Usage: .load FILE [VAR]"
  end

  local filename = args[1]
  local var_name = args[2]

  local file = io.open(filename, "r")
  if not file then
    return nil, "Failed to open file: " .. filename
  end

  local content = file:read("*all")
  file:close()

  local fn, err = load(content, filename, "t", self.config.context)
  if not fn then
    return nil, "Error loading file: " .. err
  end

  local ok, result = pcall(fn)
  if not ok then
    return nil, "Error executing file: " .. result
  end

  if var_name then
    self.config.context[var_name] = result
    return string.format("Loaded %s into variable '%s'", filename, var_name)
  end

  return string.format("Loaded %s", filename)
end

function M.REPL:_cmd_save(args)
  if #args == 0 then
    return nil, "Usage: .save FILE [EXPR]"
  end

  local filename = args[1]
  local expr = args[2] or "_"

  -- Get value
  local value = self.config.context[expr]
  if value == nil then
    return nil, "No such variable or expression: " .. expr
  end

  -- Format and save
  local content = self:_format_result(value)

  local file = io.open(filename, "w")
  if not file then
    return nil, "Failed to create file: " .. filename
  end

  file:write(content)
  file:close()

  return string.format("Saved to %s", filename)
end

function M.REPL:_cmd_reset(args)
  self.config.context = {}
  self:_setup_builtins()
  return "Context reset."
end

-- =============================================================================
-- Helper Methods
-- =============================================================================

function M.REPL:_setup_builtins()
  -- Add common utilities
  self.config.context.print = print
  self.config.context.p = function(...)
    local args = {...}
    for i, v in ipairs(args) do
      args[i] = self:_format_value(v)
    end
    print(table.concat(args, "  "))
  end

  self.config.context.pp = function(v)
    print(self:_format_value(v))
  end

  -- Add dslua modules shortcut
  self.config.context.require = require
end

function M.REPL:_format_result(result)
  if type(result) == "string" then
    return result
  elseif type(result) == "table" then
    return self:_format_value(result)
  else
    return tostring(result)
  end
end

function M.REPL:_format_value(value)
  local t = type(value)

  if t == "string" then
    return string.format('"%s"', value)
  elseif t == "number" then
    return tostring(value)
  elseif t == "boolean" then
    return tostring(value)
  elseif t == "nil" then
    return "nil"
  elseif t == "table" then
    local parts = {}
    table.insert(parts, "{")

    for k, v in pairs(value) do
      local key = type(k) == "string" and k or "[" .. tostring(k) .. "]"
      table.insert(parts, string.format("  %s = %s,", key, self:_format_value(v)))
    end

    table.insert(parts, "}")
    return table.concat(parts, "\n")
  elseif t == "function" then
    return "function"
  else
    return tostring(value)
  end
end

function M.REPL:_context_to_string()
  local parts = {}
  for k, v in pairs(self.config.context) do
    table.insert(parts, string.format("%s=%s", k, self:_format_value(v)))
  end
  return table.concat(parts, ", ")
end

function M.REPL:_add_to_history(input)
  -- Skip empty or duplicate entries
  if #input == 0 then
    return
  end

  if #self.history > 0 and self.history[#self.history] == input then
    return
  end

  table.insert(self.history, input)

  -- Limit history size
  while #self.history > self.config.history_size do
    table.remove(self.history, 1)
  end

  -- Save to file
  self:_save_history()
end

function M.REPL:_load_history()
  local file = io.open(self.config.history_file, "r")
  if not file then
    return
  end

  for line in file:lines() do
    table.insert(self.history, line)
  end

  file:close()
end

function M.REPL:_save_history()
  local file = io.open(self.config.history_file, "w")
  if not file then
    return
  end

  for _, entry in ipairs(self.history) do
    file:write(entry .. "\n")
  end

  file:close()
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

function M.repl(opts)
  return M.REPL.new(opts)
end

function M.start_repl(opts)
  local repl = M.REPL.new(opts)
  repl:start()
end

return M
