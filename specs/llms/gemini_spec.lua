describe("Gemini Provider", function()
    local llms = require("dslua.llms")

    it("should create Gemini provider", function()
        local llm = llms.Gemini("test-key", "gemini-pro")

        assert.is.equal("test-key", llm:APIKey())
        assert.is.equal("gemini-pro", llm:Model())
    end)

    it("should build Gemini request body", function()
        local llm = llms.Gemini("test-key", "gemini-pro")

        local body = llm:_buildRequestBody("Hello", {})

        assert.is_not_nil(body.contents)
        assert.is.equal(1, #body.contents)
        assert.is_not_nil(body.contents[1].parts)
    end)

    it("should make real API call when API key provided", function()
        local api_key = os.getenv("GEMINI_API_KEY")
        if not api_key then
            pending("GEMINI_API_KEY environment variable not set")
            return
        end

        local llm = llms.Gemini(api_key, "gemini-pro")
        local ctx = require("dslua.core.context").new()

        local result = llm:Complete(ctx, "Say 'test'")

        assert.is_not_nil(result.content)
    end)
end)
