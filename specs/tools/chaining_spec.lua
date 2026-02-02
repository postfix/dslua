-- specs/tools/chaining_spec.lua
-- Tests for tool chaining and composition

describe("Tool Chaining", function()
  local Tool = require("dslua.tools.base")
  local Chaining = require("dslua.tools.chaining")

  -- Helper to create mock tool
  local function createMockTool(name, fn)
    return Tool.new(name, {
      description = "Mock tool " .. name,
      func = fn or function(args)
        return {result = name .. "_result", input = args}
      end
    })
  end

  describe("ToolChain", function()
    it("should create chain with name and config", function()
      local chain = Chaining.ToolChain.new("test_chain", {
        description = "Test chain",
        tools = {}
      })

      assert.is.equal("test_chain", chain:Name())
      assert.is.equal("Test chain", chain:Description())
    end)

    it("should execute tools sequentially", function()
      local call_order = {}

      local tool1 = createMockTool("tool1", function(args)
        table.insert(call_order, "tool1")
        return {value = (args.value or 0) + 1}
      end)

      local tool2 = createMockTool("tool2", function(args)
        table.insert(call_order, "tool2")
        return {value = args.value + 2}
      end)

      local tool3 = createMockTool("tool3", function(args)
        table.insert(call_order, "tool3")
        return {value = args.value + 3}
      end)

      local chain = Chaining.ToolChain.new("add_chain", {
        tools = {tool1, tool2, tool3},
        pass_output = true
      })

      local result = chain:Execute({value = 0})

      assert.is.equal("success", result._chain_result)
      assert.is.equal(6, result.final_output.value)
      assert.is.same({"tool1", "tool2", "tool3"}, call_order)
    end)

    it("should stop on error when stop_on_error is true", function()
      local tool1 = createMockTool("tool1", function(args)
        return {value = 1}
      end)

      local tool2 = createMockTool("tool2", function(args)
        error("Tool 2 failed")
      end)

      local tool3 = createMockTool("tool3", function(args)
        return {value = 3}
      end)

      local chain = Chaining.ToolChain.new("failing_chain", {
        tools = {tool1, tool2, tool3},
        stop_on_error = true
      })

      local result = chain:Execute({})

      assert.is.equal("error", result._chain_result)
      assert.is.equal(2, result.stopped_at)
      assert.is.equal(1, #result.results)
      assert.is.equal(1, #result.errors)
      assert.is.equal("tool2", result.errors[1].tool)
    end)

    it("should continue on error when stop_on_error is false", function()
      local tool1 = createMockTool("tool1", function(args)
        return {value = 1}
      end)

      local tool2 = createMockTool("tool2", function(args)
        error("Tool 2 failed")
      end)

      local tool3 = createMockTool("tool3", function(args)
        return {value = 3}
      end)

      local chain = Chaining.ToolChain.new("continue_chain", {
        tools = {tool1, tool2, tool3},
        stop_on_error = false
      })

      local result = chain:Execute({})

      assert.is.equal("success", result._chain_result)
      assert.is.equal(2, #result.results)
      assert.is.equal(1, #result.errors)
    end)

    it("should not pass output when pass_output is false", function()
      local tool1 = createMockTool("tool1", function(args)
        return {value = 100}
      end)

      local tool2 = createMockTool("tool2", function(args)
        return {value = (args.value or 0) + 1}
      end)

      local chain = Chaining.ToolChain.new("no_pass_chain", {
        tools = {tool1, tool2},
        pass_output = false
      })

      local result = chain:Execute({value = 5})

      -- tool2 should get original input, not tool1's output
      assert.is.equal(6, result.final_output.value)  -- 5 + 1, not 100 + 1
    end)

    it("should support adding tools dynamically", function()
      local tool1 = createMockTool("tool1")
      local tool2 = createMockTool("tool2")

      local chain = Chaining.ToolChain.new("dynamic_chain", {
        tools = {tool1}
      })

      assert.is.equal(1, #chain:Tools())

      chain:AddTool(tool2)

      assert.is.equal(2, #chain:Tools())
    end)
  end)

  describe("ToolParallel", function()
    it("should create parallel tool with config", function()
      local parallel = Chaining.ToolParallel.new("test_parallel", {
        description = "Test parallel",
        tools = {},
        merge_strategy = "all"
      })

      assert.is.equal("test_parallel", parallel:Name())
      assert.is.equal("all", parallel._merge_strategy)
    end)

    it("should execute all tools and return all results", function()
      local tool1 = createMockTool("tool1", function(args)
        return {result = "A"}
      end)

      local tool2 = createMockTool("tool2", function(args)
        return {result = "B"}
      end)

      local tool3 = createMockTool("tool3", function(args)
        return {result = "C"}
      end)

      local parallel = Chaining.ToolParallel.new("merge_all", {
        tools = {tool1, tool2, tool3},
        merge_strategy = "all"
      })

      local result = parallel:Execute({})

      assert.is.equal("complete", result._parallel_result)
      assert.is.equal(3, #result.results)
      assert.is.equal(3, #result.merged_output)
    end)

    it("should return first success with first_success strategy", function()
      local tool1 = createMockTool("tool1", function(args)
        return {result = "first"}
      end)

      local tool2 = createMockTool("tool2", function(args)
        return {result = "second"}
      end)

      local parallel = Chaining.ToolParallel.new("first_success", {
        tools = {tool1, tool2},
        merge_strategy = "first_success"
      })

      local result = parallel:Execute({})

      assert.is.equal("first", result.merged_output.result)
    end)

    it("should handle mixed success and failure", function()
      local tool1 = createMockTool("tool1", function(args)
        return {result = "success"}
      end)

      local tool2 = createMockTool("tool2", function(args)
        error("Tool 2 failed")
      end)

      local tool3 = createMockTool("tool3", function(args)
        return {result = "also_success"}
      end)

      local parallel = Chaining.ToolParallel.new("mixed", {
        tools = {tool1, tool2, tool3},
        merge_strategy = "all"
      })

      local result = parallel:Execute({})

      assert.is.equal(2, #result.results)
      assert.is.equal(1, #result.errors)
      assert.is.equal("tool2", result.errors[1].tool)
    end)

    it("should support adding tools dynamically", function()
      local tool1 = createMockTool("tool1")
      local tool2 = createMockTool("tool2")

      local parallel = Chaining.ToolParallel.new("dynamic_parallel", {
        tools = {tool1}
      })

      parallel:AddTool(tool2)

      -- Tools are stored in internal _tools
      assert.is.equal(2, #parallel._tools)
    end)
  end)

  describe("ToolCondition", function()
    it("should execute true_tool when condition is met", function()
      local true_tool = createMockTool("true_tool", function(args)
        return {executed = true, branch = "true"}
      end)

      local condition = Chaining.ToolCondition.new("test_condition", {
        condition = function(args)
          return args.value > 5
        end,
        true_tool = true_tool
      })

      local result = condition:Execute({value = 10})

      assert.is.equal("success", result._condition_result)
      assert.is_true(result.condition_met)
      assert.is.equal("true_tool", result.executed_tool)
      assert.is_true(result.output.executed)
    end)

    it("should execute false_tool when condition is not met", function()
      local true_tool = createMockTool("true_tool")
      local false_tool = createMockTool("false_tool", function(args)
        return {executed = true, branch = "false"}
      end)

      local condition = Chaining.ToolCondition.new("test_condition", {
        condition = function(args)
          return args.value > 5
        end,
        true_tool = true_tool,
        false_tool = false_tool
      })

      local result = condition:Execute({value = 2})

      assert.is.equal("success", result._condition_result)
      assert.is_false(result.condition_met)
      assert.is.equal("false_tool", result.executed_tool)
      assert.is_true(result.output.executed)
    end)

    it("should return default_output when condition not met and no false_tool", function()
      local true_tool = createMockTool("true_tool")

      local condition = Chaining.ToolCondition.new("test_condition", {
        condition = function(args)
          return args.value > 5
        end,
        true_tool = true_tool,
        default_output = {skipped = true}
      })

      local result = condition:Execute({value = 2})

      assert.is.equal("condition_not_met", result._condition_result)
      assert.is_false(result.condition_met)
      assert.is_true(result.output.skipped)
    end)

    it("should handle errors in tool execution", function()
      local true_tool = createMockTool("true_tool", function(args)
        error("Tool execution failed")
      end)

      local condition = Chaining.ToolCondition.new("test_condition", {
        condition = function(args)
          return true
        end,
        true_tool = true_tool
      })

      local result = condition:Execute({value = 10})

      assert.is.equal("error", result._condition_result)
      assert.is.truthy(result.error)
    end)
  end)

  describe("ToolLoop", function()
    it("should execute tool up to max_iterations", function()
      local iterations = {}

      local tool = createMockTool("counter", function(args)
        table.insert(iterations, args.count or 1)
        return {count = (args.count or 1) + 1}
      end)

      local loop = Chaining.ToolLoop.new("counter_loop", {
        tool = tool,
        max_iterations = 5,
        pass_output = true
      })

      local result = loop:Execute({count = 1})

      assert.is.equal("complete", result._loop_result)
      assert.is.equal("max_iterations", result.stop_reason)
      assert.is.equal(5, result.iterations)
      assert.is.equal(5, #result.results)
      assert.is.same({1, 2, 3, 4, 5}, iterations)
    end)

    it("should stop when stop_condition is met", function()
      local tool = createMockTool("accumulator", function(args)
        return {sum = (args.sum or 0) + args.add, add = args.add}
      end)

      local loop = Chaining.ToolLoop.new("sum_loop", {
        tool = tool,
        max_iterations = 100,
        pass_output = true,
        stop_condition = function(input, output, iteration)
          return output.sum >= 20
        end
      })

      local result = loop:Execute({sum = 0, add = 7})

      assert.is.equal("stopped", result._loop_result)
      assert.is.equal("condition_met", result.stop_reason)
      assert.is.equal(3, result.iterations)  -- 0 + 7 = 7, 7 + 7 = 14, 14 + 7 = 21
      assert.is.equal(21, result.final_output.sum)
    end)

    it("should stop on error", function()
      local call_count = 0

      local tool = createMockTool("failing_tool", function(args)
        call_count = call_count + 1
        if call_count == 3 then
          error("Failed on iteration 3")
        end
        return {iteration = call_count}
      end)

      local loop = Chaining.ToolLoop.new("failing_loop", {
        tool = tool,
        max_iterations = 10
      })

      local result = loop:Execute({})

      assert.is.equal("error", result._loop_result)
      assert.is.equal("error", result.stop_reason)
      assert.is.equal(3, result.iterations)
    end)

    it("should not collect results when collect_results is false", function()
      local tool = createMockTool("simple_tool", function(args)
        return {value = 1}
      end)

      local loop = Chaining.ToolLoop.new("no_collect_loop", {
        tool = tool,
        max_iterations = 3,
        collect_results = false
      })

      local result = loop:Execute({})

      assert.is.equal(0, #result.results)
    end)
  end)

  describe("CompositeTool", function()
    it("should execute all tools with default behavior", function()
      local tool1 = createMockTool("tool1", function(args)
        return {result1 = "A"}
      end)

      local tool2 = createMockTool("tool2", function(args)
        return {result2 = "B"}
      end)

      local composite = Chaining.CompositeTool.new("multi_tool", {
        tools = {tool1, tool2}
      })

      local result = composite:Execute({})

      assert.is.equal("complete", result._composite_result)
      assert.is.equal(2, #result.results)
      assert.is.equal("tool1", result.results[1].tool)
      assert.is.equal("tool2", result.results[2].tool)
    end)

    it("should use custom execute function", function()
      local tool1 = createMockTool("tool1", function(args)
        return {value = 1}
      end)

      local tool2 = createMockTool("tool2", function(args)
        return {value = 2}
      end)

      local composite = Chaining.CompositeTool.new("custom_composite", {
        tools = {tool1, tool2},
        execute_fn = function(args, tools)
          -- Sum values from both tools
          local sum = 0
          for _, tool in ipairs(tools) do
            local result = tool:Execute(args)
            sum = sum + result.value
          end
          return {total = sum}
        end
      })

      local result = composite:Execute({})

      assert.is.equal(3, result.total)
    end)

    it("should support adding tools dynamically", function()
      local tool1 = createMockTool("tool1")
      local tool2 = createMockTool("tool2")

      local composite = Chaining.CompositeTool.new("dynamic_composite", {
        tools = {tool1}
      })

      assert.is.equal(1, #composite:Tools())

      composite:AddTool(tool2)

      assert.is.equal(2, #composite:Tools())
    end)
  end)

  describe("Helper Functions", function()
    it("should create chain with helper function", function()
      local tool1 = createMockTool("tool1")
      local tool2 = createMockTool("tool2")

      local chain = Chaining.chain("test", {tool1, tool2}, {
        pass_output = true,
        stop_on_error = false
      })

      assert.is.equal("test", chain:Name())
      assert.is.equal(2, #chain:Tools())
    end)

    it("should create parallel with helper function", function()
      local tool1 = createMockTool("tool1")
      local tool2 = createMockTool("tool2")

      local parallel = Chaining.parallel("test", {tool1, tool2}, {
        merge_strategy = "first_success"
      })

      assert.is.equal("test", parallel:Name())
      assert.is.equal("first_success", parallel._merge_strategy)
    end)

    it("should create condition with helper function", function()
      local tool = createMockTool("tool")

      local condition = Chaining.condition("test", {
        condition = function(args) return true end,
        true_tool = tool
      })

      assert.is.equal("test", condition:Name())
    end)

    it("should create loop with helper function", function()
      local tool = createMockTool("tool")

      local loop = Chaining.loop("test", tool, {
        max_iterations = 5
      })

      assert.is.equal("test", loop:Name())
      assert.is.equal(5, loop._max_iterations)
    end)

    it("should create composite with helper function", function()
      local composite = Chaining.compose("test", {
        description = "Test composite"
      })

      assert.is.equal("test", composite:Name())
      assert.is.equal("Test composite", composite:Description())
    end)
  end)

  describe("Integration Tests", function()
    it("should chain parallel tools", function()
      local tool1 = createMockTool("tool1", function(args)
        return {value = 10}
      end)

      local tool2 = createMockTool("tool2", function(args)
        return {value = 20}
      end)

      local parallel = Chaining.parallel("calc", {tool1, tool2}, {
        merge_strategy = "all"
      })

      local aggregator = createMockTool("aggregator", function(args)
        local sum = 0
        for _, output in ipairs(args) do
          sum = sum + output.value
        end
        return {total = sum}
      end)

      local chain = Chaining.chain("pipeline", {parallel}, {
        pass_output = true
      })

      -- Manually call aggregator with parallel results
      local parallel_result = parallel:Execute({})
      local final_result = aggregator:Execute(parallel_result.merged_output)

      assert.is.equal(30, final_result.total)
    end)

    it("should nest conditions", function()
      local tool_a = createMockTool("tool_a", function()
        return {result = "A"}
      end)

      local tool_b = createMockTool("tool_b", function()
        return {result = "B"}
      end)

      local tool_c = createMockTool("tool_c", function()
        return {result = "C"}
      end)

      local inner_condition = Chaining.condition("inner", {
        condition = function(args) return args.x > 5 end,
        true_tool = tool_a,
        false_tool = tool_b
      })

      -- Wrap inner_condition in a tool-like interface
      local condition_wrapper = createMockTool("condition_wrapper", function(args)
        return inner_condition:Execute(args)
      end)

      local outer_condition = Chaining.condition("outer", {
        condition = function(args) return args.y > 10 end,
        true_tool = condition_wrapper,
        false_tool = tool_c
      })

      local result = outer_condition:Execute({x = 7, y = 12})

      -- y > 10 is true, x > 5 is true, so execute tool_a
      assert.is.equal("A", result.output.output.result)
    end)
  end)
end)
