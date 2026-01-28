describe("Ollama Provider", function()
    local llms = require("dslua.llms")

    it("should create Ollama provider", function()
        local llm = llms.Ollama("llama3.2")

        assert.is.equal("llama3.2", llm:Model())
        assert.is.equal("http://127.0.0.1:11434", llm:BaseURL())
    end)

    it("should make real API call to local Ollama", function()
        local llm = llms.Ollama("gpt-oss:latest")
        local ctx = require("dslua.core.context").new()

        local result = llm:Complete(ctx, "Say 'test'")

        assert.is_not_nil(result.content)
        print("✓ Ollama response:", string.sub(result.content, 1, 100))
    end)

    it("should support custom endpoint", function()
        local llm = llms.Ollama("llama3.2", {
            base_url = "http://localhost:11434"
        })

        assert.is.equal("http://localhost:11434", llm:BaseURL())
    end)
end)
