describe("ChainOfThought", function()
    local Field = require("dslua.core.field")
    local Signature = require("dslua.core.signature")
    local Context = require("dslua.core.context")

    it("should create ChainOfThought with signature", function()
        local ChainOfThought = require("dslua.modules.chain_of_thought")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local cot = ChainOfThought.new(signature)

        assert.is.equal(signature, cot:Signature())
    end)

    it("should build CoT prompt with instruction", function()
        local ChainOfThought = require("dslua.modules.chain_of_thought")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local cot = ChainOfThought.new(signature)

        local prompt = cot:_buildCOTPrompt({question = "What is 2+2?"})

        -- Use plain string matching (4th arg = true) to avoid pattern issues with hyphens
        assert.is_not_nil(string.find(prompt, "Think step-by-step", 1, true))
        assert.is_not_nil(string.find(prompt, "What is 2+2?", 1, true))
        assert.is_not_nil(string.find(prompt, "Reasoning:", 1, true))
        assert.is_not_nil(string.find(prompt, "Answer:", 1, true))
    end)

    it("should parse reasoning and answer from response", function()
        local ChainOfThought = require("dslua.modules.chain_of_thought")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local cot = ChainOfThought.new(signature)

        local response = {
            content = "Reasoning: Let's think step by step.\n\nAnswer: 4"
        }
        local result = cot:_parseOutput(response)

        assert.is.equal("4", result.answer)
        assert.is_not_nil(string.find(result.reasoning, "step by step", 1, true))
    end)

    it("should process with LLM and return structured result", function()
        local ChainOfThought = require("dslua.modules.chain_of_thought")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local cot = ChainOfThought.new(signature)

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Reasoning: 2+2=4\nAnswer: 4"}
            end
        }
        local ctx = Context.new({llm = mock_llm})

        local result = cot:Process(ctx, {question = "What is 2+2?"})

        assert.is.equal("4", result.answer)
        assert.is_not_nil(result.reasoning)
    end)
end)
