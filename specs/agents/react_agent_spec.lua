describe("ReActAgent", function()
    local ReActAgent
    local Signature
    local Registry
    local Tool
    local mock_ctx

    setup(function()
        ReActAgent = require("dslua.agents.react_agent")
        Signature = require("dslua.core.signature")
        Registry = require("dslua.tools.registry")
        Tool = require("dslua.tools.base")

        mock_ctx = {
            LLM = function(self)
                return self._mock_llm
            end
        }
    end)

    before_each(function()
        mock_ctx._mock_llm = nil
    end)

    it("should create ReActAgent with signature", function()
        local sig = Signature.new("test")
        local agent = ReActAgent.new(sig)
        assert.is.not_nil(agent)
    end)

    it("should initialize with tool registry", function()
        local sig = Signature.new("test")
        local registry = Registry.new()
        local agent = ReActAgent.new(sig, {tool_registry = registry})
        assert.is.equal(registry, agent._tool_registry)
    end)

    it("should initialize with custom max_iterations", function()
        local sig = Signature.new("test")
        local agent = ReActAgent.new(sig, {max_iterations = 5})
        assert.is.equal(5, agent._max_iterations)
    end)

    it("should initialize with custom output_mode", function()
        local sig = Signature.new("test")
        local agent = ReActAgent.new(sig, {output_mode = "structured"})
        assert.is.equal("structured", agent._output_mode)
    end)

    it("should set LLM", function()
        local sig = Signature.new("test")
        local agent = ReActAgent.new(sig)
        local mock_llm = {}
        local result = agent:WithLLM(mock_llm)
        assert.is.equal(mock_llm, agent._llm)
        assert.is.equal(agent, result)
    end)

    it("should initialize state with empty steps and summary", function()
        local sig = Signature.new("test")
        local registry = Registry.new()
        local agent = ReActAgent.new(sig, {tool_registry = registry})

        local state = agent:_initialize("test input", {})

        assert.is.not_nil(state.steps)
        assert.is.equal(0, #state.steps)
        assert.is.equal("", state.summary)
        assert.is.equal(1, state.current_iteration)
        assert.is.not_nil(state.tool_usage)
        assert.is.not_nil(state.errors)
    end)

    it("should load tools from registry", function()
        local sig = Signature.new("test")
        local registry = Registry.new()

        local test_tool = Tool.new("test", {
            description = "Test tool",
            func = function(args) return {result = "ok"} end
        })
        registry:Register("test", test_tool, {description = "Test tool"})

        local agent = ReActAgent.new(sig, {tool_registry = registry})
        local state = agent:_initialize("test", {})

        assert.is.equal(1, #state.tools)
    end)

    it("should format simple output", function()
        local sig = Signature.new("test")
        local agent = ReActAgent.new(sig, {output_mode = "simple"})
        local state = {answer = "42"}

        local result = agent:_formatSimple(state)
        assert.is.equal("42", result)
    end)

    it("should format structured output", function()
        local sig = Signature.new("test")
        local agent = ReActAgent.new(sig, {output_mode = "structured"})
        local state = {
            answer = "42",
            steps = {{iteration = 1}},
            tool_usage = {calculator = 2},
            summary = "Test summary",
            errors = {}
        }

        local result = agent:_formatStructured(state)
        assert.is.equal("42", result.answer)
        assert.is.equal(2, result.tool_usage.calculator)
        assert.is.equal("Test summary", result.summary)
        assert.is.equal(1, result.iterations)
    end)

    it("should parse tool arguments", function()
        local sig = Signature.new("test")
        local agent = ReActAgent.new(sig)

        local args = agent:_parseArgs("a=2 b=3 c=test")
        assert.is.equal(2, args.a)
        assert.is.equal(3, args.b)
        assert.is.equal("test", args.c)
    end)

    it("should parse finish step", function()
        local sig = Signature.new("test")
        local agent = ReActAgent.new(sig)

        local step = agent:_parseStep("Thought: Done\nAction: finish[42]")
        assert.is.equal("finish", step.action)
        assert.is.equal("42", step.answer)
    end)

    it("should parse tool action step", function()
        local sig = Signature.new("test")
        local agent = ReActAgent.new(sig)

        local step = agent:_parseStep("Thought: Need to calculate\nAction: calculator[a=2 b=3]")
        assert.is.equal("calculator", step.action)
        assert.is.equal("a=2 b=3", step.args)
    end)

    it("should update summary after each step", function()
        local sig = Signature.new("test")
        local agent = ReActAgent.new(sig)
        local state = {summary = ""}

        agent:_updateSummary(state, {
            iteration = 1,
            thought = "Calculate 2+2",
            action = "calculator",
            observation = "4"
        })

        -- Check summary has content
        assert.is_not.Nil(state.summary)
        assert.is_true(#state.summary > 0)

        -- The summary should contain the thought
        assert.is_true(string.find(state.summary, "Calculate 2+", 1, true) ~= nil)
    end)
end)
