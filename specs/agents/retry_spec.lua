describe("Agent Retry Logic", function()
    local BaseAgent
    local Signature

    setup(function()
        BaseAgent = require("dslua.agents.base")
        Signature = require("dslua.core.signature")
    end)

    it("should retry on retryable error", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig, {
            retry_config = {
                max_retries = 2,
                initial_delay = 10,
                backoff_multiplier = 1.5,
                retryable_errors = {"timeout", "connection refused"}
            }
        })

        local attempts = 0
        local func = function()
            attempts = attempts + 1
            if attempts < 2 then
                error("timeout occurred")
            end
            return "success"
        end

        local success, result = agent:_executeWithRetry(nil, func)

        assert.is_true(success)
        assert.is.equal("success", result)
        assert.is.equal(2, attempts)
    end)

    it("should fail after max retries", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig, {
            retry_config = {
                max_retries = 3,
                initial_delay = 10,
                backoff_multiplier = 2.0,
                retryable_errors = {"timeout"}
            }
        })

        local attempts = 0
        local func = function()
            attempts = attempts + 1
            error("timeout occurred")
        end

        local success, result = agent:_executeWithRetry(nil, func)

        assert.is_false(success)
        assert.is_equal(4, attempts) -- initial + 3 retries
        assert.is_not_nil(result)
    end)

    it("should not retry on non-retryable error", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig, {
            retry_config = {
                max_retries = 3,
                initial_delay = 10,
                backoff_multiplier = 2.0,
                retryable_errors = {"timeout"}
            }
        })

        local attempts = 0
        local func = function()
            attempts = attempts + 1
            error("invalid input")
        end

        local success, result = agent:_executeWithRetry(nil, func)

        assert.is_false(success)
        assert.is_equal(1, attempts) -- no retries
    end)

    it("should identify retryable error by pattern", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig, {
            retry_config = {
                retryable_errors = {"timeout", "connection refused"}
            }
        })

        assert.is_true(agent:_isRetryableError("timeout after 30s", {"timeout"}))
        assert.is_true(agent:_isRetryableError("Connection refused by peer", {"connection refused"}))
        assert.is_false(agent:_isRetryableError("Syntax error", {"timeout"}))
    end)

    it("should handle case-insensitive error matching", function()
        local sig = Signature.new("test")
        local agent = BaseAgent.new(sig, {
            retry_config = {
                retryable_errors = {"timeout"}
            }
        })

        assert.is_true(agent:_isRetryableError("TIMEOUT occurred", {"timeout"}))
        assert.is_true(agent:_isRetryableError("Timeout", {"timeout"}))
    end)
end)
