describe("Optimizer Integration", function()
    local BootstrapFewShot
    local Signature
    local Field
    local Predict

    setup(function()
        BootstrapFewShot = require("dslua.optimizers.bootstrap_fewshot")
        Signature = require("dslua.core.signature")
        Field = require("dslua.core.field")
        Predict = require("dslua.modules.predict")
    end)

    it("should complete full optimizer workflow", function()
        -- 1. Create signature
        local sig = Signature.new(
            {Field.new("math_question")},
            {Field.new("answer")}
        )

        -- 2. Create base module
        local module = Predict.new(sig)

        -- 3. Prepare training data
        local trainset = {
            {input = {math_question = "What is 2 + 3?"}, output = {answer = "5"}},
            {input = {math_question = "What is 4 + 1?"}, output = {answer = "5"}},
            {input = {math_question = "What is 3 + 3?"}, output = {answer = "6"}},
            {input = {math_question = "What is 1 + 1?"}, output = {answer = "2"}}
        }

        -- 4. Prepare validation data
        local valset = {
            {input = {math_question = "What is 5 + 2?"}, output = {answer = "7"}}
        }

        -- 5. Create optimizer
        local optimizer = BootstrapFewShot.new(module, {
            trainset = trainset,
            valset = valset,
            max_bootstraps = 3,
            max_labeled_demos = 2
        })

        -- 6. Mock LLM
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                -- Check if prompt has demonstrations
                local has_demos = prompt:match("2 %+ 3") or prompt:match("4 %+ 1")
                if has_demos then
                    return {answer = "7"}
                end
                return {answer = "unknown"}
            end
        }

        local ctx = require("dslua.core.context").new({llm = mock_llm})

        -- 7. Compile optimized program
        local optimized = optimizer:Compile(ctx, 3)

        assert.is_not_nil(optimized)
        assert.is_not_nil(optimized._demonstrations)

        -- 8. Test optimized program
        local result = optimized:Process(ctx, {math_question = "What is 5 + 2?"})

        assert.is.equal("7", result.answer)
    end)

    it("should improve accuracy with demonstrations", function()
        local sig = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local module = Predict.new(sig)

        local trainset = {
            {input = {question = "2+2"}, output = {answer = "4"}},
            {input = {question = "3+3"}, output = {answer = "6"}},
            {input = {question = "4+4"}, output = {answer = "8"}}
        }

        local valset = {
            {input = {question = "5+5"}, output = {answer = "10"}}
        }

        local optimizer = BootstrapFewShot.new(module, {
            trainset = trainset,
            valset = valset,
            max_bootstraps = 5,
            max_labeled_demos = 3
        })

        -- Mock LLM that learns from demos
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                -- If prompt shows pattern "X+Y = Z", follow it
                if prompt:match("2%+2") and prompt:match("4") then
                    return {answer = "10"}
                end
                return {answer = "I don't know"}
            end
        }

        local ctx = require("dslua.core.context").new({llm = mock_llm})

        local optimized = optimizer:Compile(ctx, 5)

        -- Should include demonstrations
        assert.is_true(#optimized._demonstrations > 0)
    end)
end)
