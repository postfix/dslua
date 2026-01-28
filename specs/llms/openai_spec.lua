describe("OpenAI Provider", function()
    it("should create OpenAI provider with API key and model", function()
        local llms = require("dslua.llms")
        local llm = llms.OpenAI("test-key", "gpt-4")

        assert.is.equal("test-key", llm:APIKey())
        assert.is.equal("gpt-4", llm:Model())
        assert.is.equal("https://api.openai.com/v1", llm:BaseURL())
    end)

    it("should support custom base URL", function()
        local llms = require("dslua.llms")
        local llm2 = llms.OpenAI("test-key", "gpt-4", {
            base_url = "https://custom.example.com/v1"
        })

        assert.is.equal("https://custom.example.com/v1", llm2:BaseURL())
    end)

    it("should build completion request body", function()
        local llms = require("dslua.llms")
        local llm2 = llms.OpenAI("test-key", "gpt-4")

        local body = llm2:_buildRequestBody("Hello, world!", {temperature = 0.7})

        assert.is.equal("gpt-4", body.model)
        assert.is.equal(1, #body.messages)
        assert.is.equal("user", body.messages[1].role)
        assert.is.equal("Hello, world!", body.messages[1].content)
        assert.is.equal(0.7, body.temperature)
    end)
end)

describe("OpenAI Provider with HTTP", function()
    local llms = require("dslua.llms")

    it("should make real API call when API key provided", function()
        -- Only run if OPENAI_API_KEY is set
        local api_key = os.getenv("OPENAI_API_KEY")
        if not api_key then
            pending("OPENAI_API_KEY environment variable not set")
            return
        end

        local llm = llms.OpenAI(api_key, "gpt-3.5-turbo")
        local ctx = require("dslua.core.context").new()

        local result = llm:Complete(ctx, "Say 'test'")

        assert.is_not_nil(result.content)
        assert.is_not_nil(result.usage)
        assert.is_not_nil(result.model)
    end)

    it("should handle API errors gracefully", function()
        local llm = llms.OpenAI("invalid-key", "gpt-3.5-turbo")
        local ctx = require("dslua.core.context").new()

        assert.has_error(function()
            llm:Complete(ctx, "test")
        end)
    end)
end)
