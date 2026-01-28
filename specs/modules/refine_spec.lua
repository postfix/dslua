describe("Refine", function()
    local Field = require("dslua.core.field")
    local Signature = require("dslua.core.signature")
    local Context = require("dslua.core.context")

    it("should create Refine with signature", function()
        local Refine = require("dslua.modules.refine")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local refine = Refine.new(signature, {max_iterations = 2})

        assert.is.equal(signature, refine:Signature())
        assert.is.equal(2, refine._maxIterations)
    end)

    it("should build initial prompt on first iteration", function()
        local Refine = require("dslua.modules.refine")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local refine = Refine.new(signature)

        local prompt = refine:_buildRefinePrompt(
            {question = "What is 2+2?"},
            {content = ""},
            1
        )

        assert.is_not_nil(string.find(prompt, "What is 2+2?", 1, true))
        assert.is_not_nil(string.find(prompt, "Answer:", 1, true))
    end)

    it("should build refinement prompt on subsequent iterations", function()
        local Refine = require("dslua.modules.refine")
        local signature = Signature.new({}, {})
        local refine = Refine.new(signature)

        local prompt = refine:_buildRefinePrompt(
            {question = "Test"},
            {content = "Previous answer"},
            2
        )

        assert.is_not_nil(string.find(prompt, "Previous answer", 1, true))
        assert.is_not_nil(string.find(prompt, "critique", 1, true))
    end)

    it("should refine answer over multiple iterations", function()
        local Refine = require("dslua.modules.refine")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local refine = Refine.new(signature, {max_iterations = 2})

        local call_count = 0
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                call_count = call_count + 1
                if call_count == 1 then
                    return {content = "Initial answer about 2+2=4"}
                else
                    return {content = "Refined answer: 2+2 equals 4"}
                end
            end
        }

        local ctx = Context.new({llm = mock_llm})
        local result = refine:Process(ctx, {question = "What is 2+2?"})

        assert.is.equal(2, result.iterations)
        assert.is_not_nil(string.find(result.answer, "equals 4", 1, true))
    end)
end)
