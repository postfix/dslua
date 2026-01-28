describe("Anthropic Provider", function()
    local llms = require("dslua.llms")

    it("should create Anthropic provider", function()
        local llm = llms.Anthropic("test-key", "claude-3-sonnet")

        assert.is.equal("test-key", llm:APIKey())
        assert.is.equal("claude-3-sonnet", llm:Model())
        assert.is.equal("https://api.anthropic.com/v1", llm:BaseURL())
    end)

    it("should build Anthropic request body", function()
        local llm = llms.Anthropic("test-key", "claude-3-sonnet")

        local body = llm:_buildRequestBody("Hello", {max_tokens = 100})

        assert.is.equal("claude-3-sonnet", body.model)
        assert.is.equal(100, body.max_tokens)
        assert.is.equal(1, #body.messages)
        assert.is.equal("user", body.messages[1].role)
    end)

    it("should make real API call when API key provided", function()
        local api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key then
            pending("ANTHROPIC_API_KEY environment variable not set")
            return
        end

        local llm = llms.Anthropic(api_key, "claude-3-haiku-20240307")
        local ctx = require("dslua.core.context").new()

        local result = llm:Complete(ctx, "Say 'test'")

        assert.is_not_nil(result.content)
        assert.is_not_nil(result.usage)
    end)
end)
