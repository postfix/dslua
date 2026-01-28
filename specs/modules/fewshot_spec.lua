describe("FewShot Module", function()
    local FewShot
    local Signature
    local Field
    local Predict

    setup(function()
        FewShot = require("dslua.modules.fewshot")
        Signature = require("dslua.core.signature")
        Field = require("dslua.core.field")
        Predict = require("dslua.modules.predict")
    end)

    it("should create fewshot module with base module and demonstrations", function()
        local sig = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local base = Predict.new(sig)
        local demos = {
            {input = {question = "1+1"}, output = {answer = "2"}},
            {input = {question = "2+2"}, output = {answer = "4"}}
        }

        local fewshot = FewShot.new(base, demos)

        assert.is_not_nil(fewshot)
        assert.is.equal(#demos, #fewshot._demonstrations)
    end)

    it("should prepend demonstrations to prompt", function()
        local sig = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local base = Predict.new(sig)

        local demos = {
            {input = {question = "1+1"}, output = {answer = "2"}},
            {input = {question = "2+2"}, output = {answer = "4"}}
        }

        local fewshot = FewShot.new(base, demos)

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                -- Check that prompt contains demonstrations
                assert.is_true(prompt:find("question: 1%+1") ~= nil)
                assert.is_true(prompt:find("answer: 2") ~= nil)
                assert.is_true(prompt:find("question: 2%+2") ~= nil)
                assert.is_true(prompt:find("answer: 4") ~= nil)
                return {answer = "5"}
            end
        }

        fewshot:WithLLM(mock_llm)
        local ctx = require("dslua.core.context").new({})

        local result = fewshot:Process(ctx, {question = "3+2"})

        assert.is.equal("5", result.answer)
    end)

    it("should format demonstrations as question-answer pairs", function()
        local sig = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local base = Predict.new(sig)
        local demos = {
            {input = {question = "What is 1+1?"}, output = {answer = "2"}},
            {input = {question = "What is 2+2?"}, output = {answer = "4"}}
        }

        local fewshot = FewShot.new(base, demos)

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                -- Verify format: "question: ...\nanswer: ..."
                assert.is_true(prompt:find("question: What is 1%+1%?") ~= nil)
                assert.is_true(prompt:find("answer: 2") ~= nil)
                return {answer = "6"}
            end
        }

        fewshot:WithLLM(mock_llm)
        local ctx = require("dslua.core.context").new({})

        fewshot:Process(ctx, {question = "What is 3+3?"})
    end)

    it("should handle empty demonstrations", function()
        local sig = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local base = Predict.new(sig)
        local fewshot = FewShot.new(base, {})

        assert.is.equal(0, #fewshot._demonstrations)
    end)
end)
