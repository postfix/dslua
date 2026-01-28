describe("Package Integration", function()
    it("should expose all core types from main package", function()
        local dslua = require("dslua")

        assert.is.truthy(dslua.Field)
        assert.is.truthy(dslua.Signature)
        assert.is.truthy(dslua.Context)
        assert.is.truthy(dslua.Predict)
        assert.is.truthy(dslua.llms)
    end)

    it("should support complete end-to-end flow", function()
        local dslua = require("dslua")

        -- Create signature
        local signature = dslua.Signature.new(
            {dslua.Field.new("question")},
            {dslua.Field.new("answer")}
        )

        -- Create module
        local predict = dslua.Predict.new(signature)

        -- Create mock LLM
        local mock_llm = {
            Complete = function(self, ctx, prompt, opts)
                return {answer = "42"}
            end
        }

        -- Create context with LLM
        local ctx = dslua.Context.new({llm = mock_llm})

        -- Execute
        local result = predict:Process(ctx, {question = "What is 6*7?"})

        assert.is.equal("42", result.answer)
    end)

    it("should create OpenAI LLM via factory", function()
        local dslua = require("dslua")
        local llm = dslua.llms.OpenAI("test-key", "gpt-4")

        assert.is.equal("gpt-4", llm:Model())
        assert.is.equal("test-key", llm:APIKey())
    end)
end)
