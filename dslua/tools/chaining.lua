-- dslua/tools/chaining.lua
-- Tool Chaining and Composition - Combine tools into pipelines

local M = {}

-- =============================================================================
-- ToolChain - Sequential tool execution
-- =============================================================================

M.ToolChain = {}
M.ToolChain.__index = M.ToolChain

function M.ToolChain.new(name, config)
  local self = {
    _name = name or "chain",
    _description = config.description or "Sequential tool chain",
    _tools = config.tools or {},
    _pass_output = config.pass_output ~= false,  -- default true
    _stop_on_error = config.stop_on_error ~= false,  -- default true
    _metadata = config.metadata or {}
  }
  setmetatable(self, M.ToolChain)
  return self
end

function M.ToolChain:Execute(args)
  local original_input = args
  local current_input = args
  local final_output = nil
  local results = {}
  local errors = {}

  for i, tool in ipairs(self._tools) do
    local success, result = pcall(function()
      return tool:Execute(current_input)
    end)

    if success then
      table.insert(results, {
        tool = tool:Name(),
        output = result,
        success = true
      })

      -- Track the last successful output
      final_output = result

      -- Pass output to next tool if enabled
      if self._pass_output then
        current_input = result
      else
        -- Reset to original input for next tool
        current_input = original_input
      end
    else
      table.insert(errors, {
        tool = tool:Name(),
        error = tostring(result),
        success = false,
        index = i
      })

      if self._stop_on_error then
        return {
          _chain_result = "error",
          _chain_name = self._name,
          results = results,
          errors = errors,
          stopped_at = i
        }
      end
    end
  end

  return {
    _chain_result = "success",
    _chain_name = self._name,
    final_output = final_output or original_input,
    results = results,
    errors = errors
  }
end

function M.ToolChain:Name()
  return self._name
end

function M.ToolChain:Description()
  return self._description
end

function M.ToolChain:AddTool(tool)
  table.insert(self._tools, tool)
  return self
end

function M.ToolChain:Tools()
  return self._tools
end

-- =============================================================================
-- ToolParallel - Parallel tool execution
-- =============================================================================

M.ToolParallel = {}
M.ToolParallel.__index = M.ToolParallel

function M.ToolParallel.new(name, config)
  local self = {
    _name = name or "parallel",
    _description = config.description or "Parallel tool execution",
    _tools = config.tools or {},
    _merge_strategy = config.merge_strategy or "all",  -- "all", "first_success", "majority"
    _timeout = config.timeout or 30
  }
  setmetatable(self, M.ToolParallel)
  return self
end

function M.ToolParallel:Execute(args)
  local results = {}
  local errors = {}
  local start_time = os.clock()

  for i, tool in ipairs(self._tools) do
    local success, result = pcall(function()
      return tool:Execute(args)
    end)

    local elapsed = (os.clock() - start_time) * 1000

    if success then
      table.insert(results, {
        tool = tool:Name(),
        output = result,
        latency_ms = elapsed,
        success = true
      })
    else
      table.insert(errors, {
        tool = tool:Name(),
        error = tostring(result),
        latency_ms = elapsed,
        success = false,
        index = i
      })
    end
  end

  -- Merge based on strategy
  local merged = self:_mergeResults(results, errors)

  return {
    _parallel_result = "complete",
    _parallel_name = self._name,
    merge_strategy = self._merge_strategy,
    merged_output = merged,
    results = results,
    errors = errors,
    total_latency_ms = (os.clock() - start_time) * 1000
  }
end

function M.ToolParallel:_mergeResults(results, errors)
  if self._merge_strategy == "first_success" then
    for _, result in ipairs(results) do
      if result.success then
        return result.output
      end
    end
    return nil
  elseif self._merge_strategy == "all" then
    local all_outputs = {}
    for _, result in ipairs(results) do
      if result.success then
        table.insert(all_outputs, result.output)
      end
    end
    return all_outputs
  elseif self._merge_strategy == "majority" then
    -- For simple outputs, find the most common
    local counts = {}
    for _, result in ipairs(results) do
      if result.success then
        local key = tostring(result.output)
        counts[key] = (counts[key] or 0) + 1
      end
    end

    local max_count = 0
    local majority = nil
    for key, count in pairs(counts) do
      if count > max_count then
        max_count = count
        majority = key
      end
    end
    return majority
  end

  return nil
end

function M.ToolParallel:Name()
  return self._name
end

function M.ToolParallel:Description()
  return self._description
end

function M.ToolParallel:AddTool(tool)
  table.insert(self._tools, tool)
  return self
end

-- =============================================================================
-- ToolCondition - Conditional tool execution
-- =============================================================================

M.ToolCondition = {}
M.ToolCondition.__index = M.ToolCondition

function M.ToolCondition.new(name, config)
  local self = {
    _name = name or "condition",
    _description = config.description or "Conditional tool execution",
    _condition = config.condition,  -- function(args) -> boolean
    _true_tool = config.true_tool,  -- tool to execute if condition is true
    _false_tool = config.false_tool,  -- tool to execute if condition is false (optional)
    _default_output = config.default_output  -- output if condition false and no false_tool
  }
  setmetatable(self, M.ToolCondition)
  return self
end

function M.ToolCondition:Execute(args)
  local condition_met = self._condition(args)

  if condition_met then
    if not self._true_tool then
      return {
        _condition_result = "no_tool",
        _condition_name = self._name,
        condition_met = condition_met,
        output = self._default_output
      }
    end

    local success, result = pcall(function()
      return self._true_tool:Execute(args)
    end)

    return {
      _condition_result = success and "success" or "error",
      _condition_name = self._name,
      condition_met = condition_met,
      executed_tool = self._true_tool:Name(),
      output = success and result or nil,
      error = success and nil or tostring(result)
    }
  else
    if self._false_tool then
      local success, result = pcall(function()
        return self._false_tool:Execute(args)
      end)

      return {
        _condition_result = success and "success" or "error",
        _condition_name = self._name,
        condition_met = condition_met,
        executed_tool = self._false_tool:Name(),
        output = success and result or nil,
        error = success and nil or tostring(result)
      }
    else
      return {
        _condition_result = "condition_not_met",
        _condition_name = self._name,
        condition_met = condition_met,
        output = self._default_output
      }
    end
  end
end

function M.ToolCondition:Name()
  return self._name
end

function M.ToolCondition:Description()
  return self._description
end

-- =============================================================================
-- ToolLoop - Repeated tool execution
-- =============================================================================

M.ToolLoop = {}
M.ToolLoop.__index = M.ToolLoop

function M.ToolLoop.new(name, config)
  local self = {
    _name = name or "loop",
    _description = config.description or "Repeated tool execution",
    _tool = config.tool,
    _max_iterations = config.max_iterations or 10,
    _stop_condition = config.stop_condition,  -- function(args, result, iteration) -> boolean
    _collect_results = config.collect_results ~= false,  -- default true
    _pass_output = config.pass_output ~= false  -- default true
  }
  setmetatable(self, M.ToolLoop)
  return self
end

function M.ToolLoop:Execute(args)
  local current_input = args
  local results = {}
  local errors = {}

  for i = 1, self._max_iterations do
    local success, result = pcall(function()
      return self._tool:Execute(current_input)
    end)

    if success then
      if self._collect_results then
        table.insert(results, {
          iteration = i,
          output = result,
          success = true
        })
      end

      -- Check stop condition
      if self._stop_condition and self._stop_condition(current_input, result, i) then
        return {
          _loop_result = "stopped",
          _loop_name = self._name,
          iterations = i,
          final_output = result,
          results = results,
          errors = errors,
          stop_reason = "condition_met"
        }
      end

      -- Pass output to next iteration if enabled
      if self._pass_output then
        current_input = result
      end
    else
      table.insert(errors, {
        iteration = i,
        error = tostring(result),
        success = false
      })

      -- Stop on error
      return {
        _loop_result = "error",
        _loop_name = self._name,
        iterations = i,
        results = results,
        errors = errors,
        stop_reason = "error"
      }
    end
  end

  return {
    _loop_result = "complete",
    _loop_name = self._name,
    iterations = self._max_iterations,
    final_output = current_input,
    results = results,
    errors = errors,
    stop_reason = "max_iterations"
  }
end

function M.ToolLoop:Name()
  return self._name
end

function M.ToolLoop:Description()
  return self._description
end

-- =============================================================================
-- CompositeTool - Combine multiple tools into a single tool interface
-- =============================================================================

M.CompositeTool = {}
M.CompositeTool.__index = M.CompositeTool

function M.CompositeTool.new(name, config)
  local self = {
    _name = name or "composite",
    _description = config.description or "Composite tool",
    _execute_fn = config.execute_fn,  -- Custom execute function
    _tools = config.tools or {},
    _metadata = config.metadata or {}
  }
  setmetatable(self, M.CompositeTool)
  return self
end

function M.CompositeTool:Execute(args)
  if self._execute_fn then
    return self._execute_fn(args, self._tools)
  end

  -- Default: execute all tools and merge results
  local results = {}
  for i, tool in ipairs(self._tools) do
    local success, result = pcall(function()
      return tool:Execute(args)
    end)

    results[i] = {
      tool = tool:Name(),
      output = success and result or nil,
      error = success and nil or tostring(result),
      success = success
    }
  end

  return {
    _composite_result = "complete",
    _composite_name = self._name,
    results = results
  }
end

function M.CompositeTool:Name()
  return self._name
end

function M.CompositeTool:Description()
  return self._description
end

function M.CompositeTool:AddTool(tool)
  table.insert(self._tools, tool)
  return self
end

function M.CompositeTool:Tools()
  return self._tools
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

-- Create a simple chain from a list of tools
function M.chain(name, tools, opts)
  opts = opts or {}
  return M.ToolChain.new(name, {
    tools = tools,
    pass_output = opts.pass_output,
    stop_on_error = opts.stop_on_error,
    description = opts.description
  })
end

-- Create parallel execution from a list of tools
function M.parallel(name, tools, opts)
  opts = opts or {}
  return M.ToolParallel.new(name, {
    tools = tools,
    merge_strategy = opts.merge_strategy or "all",
    timeout = opts.timeout,
    description = opts.description
  })
end

-- Create conditional branching
function M.condition(name, opts)
  return M.ToolCondition.new(name, opts)
end

-- Create a loop
function M.loop(name, tool, opts)
  opts = opts or {}
  return M.ToolLoop.new(name, {
    tool = tool,
    max_iterations = opts.max_iterations or 10,
    stop_condition = opts.stop_condition,
    collect_results = opts.collect_results,
    pass_output = opts.pass_output,
    description = opts.description
  })
end

-- Create a composite tool
function M.compose(name, opts)
  return M.CompositeTool.new(name, opts)
end

return M
