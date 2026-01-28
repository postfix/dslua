describe("ReActAgent Integration", function()
    local ReActAgent
    local Signature
    local Registry
    local Calculator
    local StringHelper

    setup(function()
        ReActAgent = require("dslua.agents.react_agent")
        Signature = require("dslua.core.signature")
        Registry = require("dslua.tools.registry")
        Calculator = require("dslua.tools.builtin.calculator")
        StringHelper = require("dslua.tools.builtin.string_helper")
    end)

    it("should execute single step with mock LLM and finish", function()
        local sig = Signature.new("test")
        local registry = Registry.new()

        local calc = Calculator.new()
        registry:Register("calculator", calc, {
            description = "Performs arithmetic operations",
            category = "basic"
        })

        local agent = ReActAgent.new(sig, {
            tool_registry = registry,
            max_iterations = 5,
            output_mode = "simple"
        })

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Thought: I need to calculate\nAction: finish[42]"}
            end
        }

        agent:WithLLM(mock_llm)

        local mock_ctx = {
            LLM = function(self)
                return mock_llm
            end
        }

        local result = agent:Execute(mock_ctx, "What is the answer?")

        assert.is.equal("42", result)
    end)

    it("should execute tool call and return result", function()
        local sig = Signature.new("test")
        local registry = Registry.new()

        local calc = Calculator.new()
        registry:Register("calculator", calc, {
            description = "Performs arithmetic operations",
            category = "basic"
        })

        local agent = ReActAgent.new(sig, {
            tool_registry = registry,
            max_iterations = 5,
            output_mode = "structured"
        })

        local call_count = 0
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                call_count = call_count + 1
                if call_count == 1 then
                    return {content = "Thought: I need to add 2 and 3\nAction: calculator[operation=add a=2 b=3]"}
                else
                    return {content = "Thought: Done\nAction: finish[5]"}
                end
            end
        }

        agent:WithLLM(mock_llm)

        local mock_ctx = {
            LLM = function(self)
                return mock_llm
            end
        }

        local result = agent:Execute(mock_ctx, "What is 2 + 3?")

        assert.is.equal("5", result.answer)
        assert.is.equal(2, result.iterations)
        assert.is.equal(1, result.tool_usage.calculator)
    end)

    it("should track multiple tool calls", function()
        local sig = Signature.new("test")
        local registry = Registry.new()

        local calc = Calculator.new()
        registry:Register("calculator", calc, {
            description = "Performs arithmetic operations",
            category = "basic"
        })

        local agent = ReActAgent.new(sig, {
            tool_registry = registry,
            max_iterations = 10,
            output_mode = "structured"
        })

        local call_count = 0
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                call_count = call_count + 1
                if call_count == 1 then
                    return {content = "Thought: Add 2 and 3\nAction: calculator[operation=add a=2 b=3]"}
                elseif call_count == 2 then
                    return {content = "Thought: Multiply by 4\nAction: calculator[operation=multiply a=5 b=4]"}
                else
                    return {content = "Thought: Done\nAction: finish[20]"}
                end
            end
        }

        agent:WithLLM(mock_llm)

        local mock_ctx = {
            LLM = function(self)
                return mock_llm
            end
        }

        local result = agent:Execute(mock_ctx, "Calculate (2+3)*4")

        assert.is.equal("20", result.answer)
        assert.is.equal(2, result.tool_usage.calculator)
        assert.is.equal(3, result.iterations)
    end)

    it("should use multiple different tools", function()
        local sig = Signature.new("test")
        local registry = Registry.new()

        local calc = Calculator.new()
        local str_helper = StringHelper.new()

        registry:Register("calculator", calc, {
            description = "Performs arithmetic operations",
            category = "basic"
        })
        registry:Register("string_helper", str_helper, {
            description = "String manipulation",
            category = "basic"
        })

        local agent = ReActAgent.new(sig, {
            tool_registry = registry,
            max_iterations = 10,
            output_mode = "structured"
        })

        local call_count = 0
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                call_count = call_count + 1
                if call_count == 1 then
                    return {content = "Thought: Convert hello to uppercase\nAction: string_helper[operation=uppercase text=hello]"}
                elseif call_count == 2 then
                    return {content = "Thought: Add 5 and 3\nAction: calculator[operation=add a=5 b=3]"}
                else
                    return {content = "Thought: Done\nAction: finish[HELLO and 8]"}
                end
            end
        }

        agent:WithLLM(mock_llm)

        local mock_ctx = {
            LLM = function(self)
                return mock_llm
            end
        }

        local result = agent:Execute(mock_ctx, "Process multiple operations")

        assert.is.equal(1, result.tool_usage.string_helper)
        assert.is.equal(1, result.tool_usage.calculator)
    end)

    it("should update conversation summary", function()
        local sig = Signature.new("test")
        local registry = Registry.new()

        local calc = Calculator.new()
        registry:Register("calculator", calc, {
            description = "Performs arithmetic operations",
            category = "basic"
        })

        local agent = ReActAgent.new(sig, {
            tool_registry = registry,
            max_iterations = 10,
            output_mode = "structured"
        })

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Thought: Calculate\nAction: calculator[operation=add a=2 b=2]\nThought: Done\nAction: finish[4]"}
            end
        }

        agent:WithLLM(mock_llm)

        local mock_ctx = {
            LLM = function(self)
                return mock_llm
            end
        }

        local result = agent:Execute(mock_ctx, "What is 2+2?")

        assert.is_not.equal("", result.summary)
        assert.is_true(result.summary:find("Calculate") ~= nil)
    end)

    it("should handle tool errors gracefully", function()
        local sig = Signature.new("test")
        local registry = Registry.new()

        local calc = Calculator.new()
        registry:Register("calculator", calc, {
            description = "Performs arithmetic operations",
            category = "basic"
        })

        local agent = ReActAgent.new(sig, {
            tool_registry = registry,
            max_iterations = 10,
            output_mode = "structured"
        })

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Thought: Divide by zero\nAction: calculator[operation=divide a=10 b=0]\nThought: Done\nAction: finish[Error occurred]"}
            end
        }

        agent:WithLLM(mock_llm)

        local mock_ctx = {
            LLM = function(self)
                return mock_llm
            end
        }

        local result = agent:Execute(mock_ctx, "Divide 10 by 0")

        assert.is_true(#result.error_history > 0)
        assert.is.equal("calculator", result.error_history[1].tool)
    end)

    it("should stop at max_iterations", function()
        local sig = Signature.new("test")
        local registry = Registry.new()

        local calc = Calculator.new()
        registry:Register("calculator", calc, {
            description = "Performs arithmetic operations",
            category = "basic"
        })

        local agent = ReActAgent.new(sig, {
            tool_registry = registry,
            max_iterations = 3,
            output_mode = "structured"
        })

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Thought: Keep going\nAction: calculator[operation=add a=1 b=1]"}
            end
        }

        agent:WithLLM(mock_llm)

        local mock_ctx = {
            LLM = function(self)
                return mock_llm
            end
        }

        local result = agent:Execute(mock_ctx, "Keep calculating")

        assert.is.equal(3, result.iterations)
        assert.is.equal("No answer generated", result.answer)
    end)

    it("should handle multi-step conversation (10+ steps)", function()
        local sig = Signature.new("test")
        local registry = Registry.new()

        local calc = Calculator.new()
        registry:Register("calculator", calc, {
            description = "Performs arithmetic operations",
            category = "basic"
        })

        local agent = ReActAgent.new(sig, {
            tool_registry = registry,
            max_iterations = 15,
            output_mode = "structured"
        })

        local call_count = 0
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                call_count = call_count + 1
                if call_count < 12 then
                    return {content = "Thought: Step " .. call_count .. "\nAction: calculator[operation=add a=1 b=1]"}
                else
                    return {content = "Thought: Finally done\nAction: finish[Complete after 12 steps]"}
                end
            end
        }

        agent:WithLLM(mock_llm)

        local mock_ctx = {
            LLM = function(self)
                return mock_llm
            end
        }

        local result = agent:Execute(mock_ctx, "Long conversation")

        assert.is.equal(12, result.iterations)
        assert.is.equal("Complete after 12 steps", result.answer)
        assert.is_true(#result.summary > 100) -- Long summary
    end)
end)
