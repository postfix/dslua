describe("BaseAgent", function()
    local BaseAgent
    local Signature

    setup(function()
        BaseAgent = require("dslua.agents.base")
        Signature = require("dslua.core.signature")
    end)

    it("should create base agent with signature", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig)
        assert.is.not_nil(agent)
    end)

    it("should set default max_iterations", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig)
        assert.is.equal(10, agent._max_iterations)
    end)

    it("should allow custom max_iterations", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig, {max_iterations = 5})
        assert.is.equal(5, agent._max_iterations)
    end)

    it("should set default output_mode to simple", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig)
        assert.is.equal("simple", agent._output_mode)
    end)

    it("should allow custom output_mode", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig, {output_mode = "structured"})
        assert.is.equal("structured", agent._output_mode)
    end)

    it("should set default retry_config", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig)
        assert.is.not_nil(agent._retry_config)
        assert.is.equal(3, agent._retry_config.max_retries)
        assert.is.equal(100, agent._retry_config.initial_delay)
        assert.is.equal(2.0, agent._retry_config.backoff_multiplier)
    end)

    it("should allow custom retry_config", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig, {
            retry_config = {
                max_retries = 5,
                initial_delay = 200,
                backoff_multiplier = 3.0
            }
        })
        assert.is.equal(5, agent._retry_config.max_retries)
        assert.is.equal(200, agent._retry_config.initial_delay)
        assert.is.equal(3.0, agent._retry_config.backoff_multiplier)
    end)

    it("should identify retryable errors", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig)

        assert.is.truthy(agent:_isRetryableError("timeout occurred", {"timeout"}))
        assert.is.truthy(agent:_isRetryableError("Connection refused", {"connection refused"}))
        assert.is.falsy(agent:_isRetryableError("Invalid input", {"timeout"}))
    end)

    it("should throw error when calling unimplemented Execute", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig)

        assert.has_error(function()
            agent:Execute({}, "test")
        end, "_initialize must be implemented by subclass")
    end)

    it("should throw error for unknown output mode", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig, {output_mode = "unknown"})

        local state = {}
        assert.has_error(function()
            agent:_formatResult(state, "unknown")
        end, "Unknown output mode: unknown")
    end)
end)
