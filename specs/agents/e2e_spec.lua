describe("ReActAgent End-to-End Tests", function()
    local ReActAgent
    local Signature
    local Registry
    local Calculator
    local StringHelper
    local Ollama

    setup(function()
        ReActAgent = require("dslua.agents.react_agent")
        Signature = require("dslua.core.signature")
        Registry = require("dslua.tools.registry")
        Calculator = require("dslua.tools.builtin.calculator")
        StringHelper = require("dslua.tools.builtin.string_helper")
        Ollama = require("dslua.llms.providers.ollama")
    end)

    it("should execute with real tools and mock LLM", function()
        local sig = Signature.new("test")
        local registry = Registry.new()

        local calc = Calculator.new()
        local str_helper = StringHelper.new()

        registry:Register("calculator", calc, {
            description = "Performs arithmetic operations: add, subtract, multiply, divide",
            category = "basic",
            parameters = {"operation", "a", "b"},
            examples = {"calculator[operation=add a=2 b=3]"}
        })

        registry:Register("string_helper", str_helper, {
            description = "Performs string operations: length, uppercase, lowercase, trim, reverse",
            category = "basic",
            parameters = {"operation", "text"},
            examples = {"string_helper[operation=uppercase text=hello]"}
        })

        local agent = ReActAgent.new(sig, {
            tool_registry = registry,
            max_iterations = 10,
            output_mode = "structured"
        })

        -- Mock LLM that simulates realistic multi-step reasoning
        local step = 0
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                step = step + 1
                if step == 1 then
                    return {content = "Thought: I need to calculate the sum of 15 and 27\nAction: calculator[operation=add a=15 b=27]"}
                elseif step == 2 then
                    return {content = "Thought: The result is 42. Now I need to convert this to uppercase\nAction: string_helper[operation=uppercase text=42]"}
                else
                    return {content = "Thought: I have the final answer\nAction: finish[The sum is 42, which as uppercase is 42]"}
                end
            end
        }

        agent:WithLLM(mock_llm)

        local mock_ctx = {
            LLM = function(self)
                return mock_llm
            end
        }

        local result = agent:Execute(mock_ctx, "Add 15 and 27, then convert to uppercase")

        assert.is_not.Nil(result.answer)
        assert.is_not.Nil(result.tool_usage)
        assert.is_true(result.tool_usage.calculator >= 1)
        assert.is_true(result.iterations >= 2)
        assert.is_not.Nil(result.reasoning)
        assert.is_true(#result.reasoning > 0)
    end)

    it("should handle complex multi-step calculation", function()
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

        -- Mock LLM that performs ((2+3)*4)-5 = 15
        local step = 0
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                step = step + 1
                if step == 1 then
                    return {content = "Thought: First add 2 and 3\nAction: calculator[operation=add a=2 b=3]"}
                elseif step == 2 then
                    return {content = "Thought: Got 5, now multiply by 4\nAction: calculator[operation=multiply a=5 b=4]"}
                elseif step == 3 then
                    return {content = "Thought: Got 20, now subtract 5\nAction: calculator[operation=subtract a=20 b=5]"}
                else
                    return {content = "Thought: Final result is 15\nAction: finish[15]"}
                end
            end
        }

        agent:WithLLM(mock_llm)

        local mock_ctx = {
            LLM = function(self)
                return mock_llm
            end
        }

        local result = agent:Execute(mock_ctx, "Calculate ((2+3)*4)-5")

        assert.is.equal("15", result.answer)
        assert.is.equal(3, result.tool_usage.calculator)
        assert.is.equal(4, result.iterations)
    end)

    it("should recover from tool errors and continue", function()
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

        local step = 0
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                step = step + 1
                if step == 1 then
                    -- Try to divide by zero
                    return {content = "Thought: I'll try to divide 10 by 0\nAction: calculator[operation=divide a=10 b=0]"}
                elseif step == 2 then
                    -- Recover with valid operation
                    return {content = "Thought: Division by zero failed. Let me multiply instead\nAction: calculator[operation=multiply a=5 b=4]"}
                else
                    return {content = "Thought: Got 20\nAction: finish[20]"}
                end
            end
        }

        agent:WithLLM(mock_llm)

        local mock_ctx = {
            LLM = function(self)
                return mock_llm
            end
        }

        local result = agent:Execute(mock_ctx, "Calculate something")

        -- Should have error history
        assert.is_true(#result.error_history > 0)
        -- But should still complete successfully
        assert.is.equal("20", result.answer)
        assert.is.equal(3, result.iterations)
    end)

    it("should work with Ollama provider (if available)", function()
        local ollama_url = os.getenv("OLLAMA_URL") or "http://localhost:11434"
        local ollama_model = os.getenv("OLLAMA_MODEL") or "llama2"

        -- Skip test if Ollama is not available
        local http = require("dslua.llms.http")
        local success, err = pcall(function()
            local curl = require("plenary.curl")
            local response = curl.get(ollama_url .. "/api/tags", {
                timeout = 1000,
                reject_invalid = false
            })
            return response.status == 200
        end)

        if not success then
            pending("Ollama not available at " .. ollama_url)
            return
        end

        local sig = Signature.new("e2e_test")
        local registry = Registry.new()

        local calc = Calculator.new()
        registry:Register("calculator", calc, {
            description = "Performs arithmetic operations",
            category = "basic"
        })

        local agent = ReActAgent.new(sig, {
            tool_registry = registry,
            max_iterations = 10,
            output_mode = "simple"
        })

        local ollama = Ollama.new(ollama_model, {
            base_url = ollama_url
        })

        agent:WithLLM(ollama)

        local mock_ctx = {
            LLM = function(self)
                return ollama
            end
        }

        local result = agent:Execute(mock_ctx, "What is 2 + 2? Use the calculator tool.")

        assert.is_not.Nil(result)
        assert.is_not.equal("", result)
        assert.is_not.equal("No answer generated", result)
    end)
end)
