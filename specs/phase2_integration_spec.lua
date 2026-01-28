describe("Phase 2 Integration", function()
    it("should expose all Phase 2 modules from main package", function()
        local dslua = require("dslua")

        assert.is.truthy(dslua.ChainOfThought)
        assert.is.truthy(dslua.ReAct)
        assert.is.truthy(dslua.Refine)
    end)

    it("should expose all providers from main package", function()
        local dslua = require("dslua")

        assert.is.truthy(dslua.llms.Anthropic)
        assert.is.truthy(dslua.llms.Gemini)
    end)

    it("should support complete ChainOfThought flow with real provider", function()
        local dslua = require("dslua")
        local api_key = os.getenv("OPENAI_API_KEY")

        if not api_key then
            pending("OPENAI_API_KEY not set")
            return
        end

        local signature = dslua.Signature.new(
            {dslua.Field.new("question")},
            {dslua.Field.new("answer")}
        )
        local cot = dslua.ChainOfThought.new(signature)
        local llm = dslua.llms.OpenAI(api_key, "gpt-3.5-turbo")
        local ctx = dslua.Context.new({llm = llm})

        local result = cot:Process(ctx, {question = "What is 2+2?"})

        assert.is_not_nil(result.answer)
        assert.is_not_nil(result.reasoning)
    end)
end)
