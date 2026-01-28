describe("Predict", function()
    local Field = require("dslua.core.field")
    local Signature = require("dslua.core.signature")
    local Context = require("dslua.core.context")

    it("should create predict with signature", function()
        local Predict = require("dslua.modules.predict")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local predict = Predict.new(signature)

        assert.is.equal(signature, predict:Signature())
    end)

    it("should build prompt from input and signature", function()
        local Predict = require("dslua.modules.predict")
        local signature = Signature.new(
            {Field.new("question", {desc = "The question"})},
            {Field.new("answer", {desc = "The answer"})}
        )
        local predict = Predict.new(signature)

        local prompt = predict:_buildPrompt({question = "What is 2+2?"})

        assert.is.truthy(string.find(prompt, "question"))
        assert.is.truthy(string.find(prompt, "What is 2+2?"))
    end)

    it("should use context LLM if available", function()
        local Predict = require("dslua.modules.predict")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local predict = Predict.new(signature)

        local mock_llm = {
            Complete = function(self, ctx, prompt, opts)
                return {answer = "42"}
            end
        }
        local ctx = Context.new({llm = mock_llm})

        local result = predict:Process(ctx, {question = "What is 6*7?"})

        assert.is.equal("42", result.answer)
    end)

    it("should use module LLM if context LLM not available", function()
        local Predict = require("dslua.modules.predict")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local predict = Predict.new(signature)

        local mock_llm = {
            Complete = function(self, ctx, prompt, opts)
                return {answer = "Paris"}
            end
        }
        predict:WithLLM(mock_llm)
        local ctx = Context.new()

        local result = predict:Process(ctx, {question = "Capital of France?"})

        assert.is.equal("Paris", result.answer)
    end)
end)
