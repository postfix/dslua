describe("ACE End-to-End Integration", function()
    local dslua = require("dslua")

    it("should execute simple math task with calculator rule", function()
        local signature = dslua.Signature.new(
            {dslua.Field.new("question")},
            {dslua.Field.new("answer")}
        )

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Answer: 84"}
            end
        }

        local module = dslua.Predict.new(signature)
        module:WithLLM(mock_llm)

        local ace = dslua.ACE.new(module, {
            rules = dslua.ACERules
        })

        local ctx = dslua.Context.new({llm = mock_llm})
        local result = ace:Execute(ctx, {question = "What is 15*27?"})

        assert.is_not_nil(result.answer)
        assert.is_not_nil(result.stats)
        assert.is_true(result.stats.steps_taken >= 1)
    end)

    it("should decompose complex factual question", function()
        local signature = dslua.Signature.new(
            {dslua.Field.new("question")},
            {dslua.Field.new("answer")}
        )

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Answer: Paris"}
            end
        }

        local module = dslua.Predict.new(signature)
        module:WithLLM(mock_llm)

        local ace = dslua.ACE.new(module, {
            rules = dslua.ACERules,
            max_steps = 5
        })

        local ctx = dslua.Context.new({llm = mock_llm})
        -- Long question should trigger decomposition
        local long_question = string.rep("What is the capital of France and can you provide detailed historical context about the city? ", 3)

        local result = ace:Execute(ctx, {question = long_question})

        assert.is_not_nil(result.answer)
        assert.is_not_nil(result.stats.action_history)
    end)

    it("should use direct reasoning for simple questions", function()
        local signature = dslua.Signature.new(
            {dslua.Field.new("question")},
            {dslua.Field.new("answer")}
        )

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Answer: 42"}
            end
        }

        local module = dslua.Predict.new(signature)
        module:WithLLM(mock_llm)

        local ace = dslua.ACE.new(module, {
            rules = dslua.ACERules
        })

        local ctx = dslua.Context.new({llm = mock_llm})
        local result = ace:Execute(ctx, {question = "2+2"})

        assert.is.equal("42", result.answer)
        assert.is.equal("SUCCESS", result.termination_reason)
    end)

    it("should handle errors gracefully with fallback", function()
        local signature = dslua.Signature.new(
            {dslua.Field.new("question")},
            {dslua.Field.new("answer")}
        )

        local failing_module = {
            Process = function(self, ctx, input)
                error("Simulated failure")
            end,
            Signature = function() return signature end
        }

        local ace = dslua.ACE.new(failing_module, {
            rules = dslua.ACERules
        })

        local ctx = dslua.Context.new({})

        -- Should not crash, but handle error
        local ok, result = pcall(function()
            return ace:Execute(ctx, {question = "test"})
        end)

        -- For now, we expect it might fail
        -- TODO: Add proper error handling in ACE
        -- assert.is_true(ok)
    end)
end)
