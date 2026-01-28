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
        local llm = llms.OpenAI("test-key", "gpt-4", {
            base_url = "https://custom.example.com/v1"
        })

        assert.is.equal("https://custom.example.com/v1", llm:BaseURL())
    end)

    it("should build completion request body", function()
        local llms = require("dslua.llms")
        local llm = llms.OpenAI("test-key", "gpt-4")

        local body = llm:_buildRequestBody("Hello, world!", {temperature = 0.7})

        assert.is.equal("gpt-4", body.model)
        assert.is.equal(1, #body.messages)
        assert.is.equal("user", body.messages[1].role)
        assert.is.equal("Hello, world!", body.messages[1].content)
        assert.is.equal(0.7, body.temperature)
    end)
end)
