describe("Optimizer Base", function()
    local BaseOptimizer

    setup(function()
        BaseOptimizer = require("dslua.optimizers.base")
    end)

    it("should create base optimizer with module and dataset", function()
        local Signature = require("dslua.core.signature")
        local Predict = require("dslua.modules.predict")

        local sig = Signature.new(
            {require("dslua.core.field").new("question")},
            {require("dslua.core.field").new("answer")}
        )

        local module = Predict.new(sig)
        local dataset = {
            {input = {question = "2+2"}, output = {answer = "4"}},
            {input = {question = "3+3"}, output = {answer = "6"}}
        }

        local optimizer = BaseOptimizer.new(module, {
            dataset = dataset,
            metric = function(result, expected)
                return result.answer == expected.answer and 1 or 0
            end
        })

        assert.is_not_nil(optimizer)
        assert.is.equal(module, optimizer._module)
        assert.is.equal(2, #optimizer._dataset)
    end)

    it("should throw error when Compile is not implemented", function()
        local Signature = require("dslua.core.signature")
        local Predict = require("dslua.modules.predict")

        local sig = Signature.new(
            {require("dslua.core.field").new("question")},
            {require("dslua.core.field").new("answer")}
        )

        local module = Predict.new(sig)
        local optimizer = BaseOptimizer.new(module, {dataset = {}})

        local ctx = require("dslua.core.context").new({})

        assert.has_error(function()
            optimizer:Compile(ctx, 5)
        end, "Compile must be implemented by subclass")
    end)

    it("should evaluate program on dataset", function()
        local Signature = require("dslua.core.signature")
        local Field = require("dslua.core.field")
        local Predict = require("dslua.modules.predict")

        local sig = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local module = Predict.new(sig)
        local dataset = {
            {input = {question = "What is 2+2?"}, output = {answer = "4"}},
            {input = {question = "What is 3+3?"}, output = {answer = "6"}}
        }

        local optimizer = BaseOptimizer.new(module, {
            dataset = dataset,
            metric = function(result, expected)
                return result.answer == expected.answer and 1 or 0
            end
        })

        -- Mock LLM that returns parsed results
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                local q = prompt:match("question: (.-)%s*$")
                if q == "What is 2+2?" then
                    return {answer = "4"}
                else
                    return {answer = "6"}
                end
            end
        }

        local ctx = require("dslua.core.context").new({llm = mock_llm})

        local score = optimizer:Evaluate(ctx, module)

        assert.is.equal(1.0, score) -- Both correct
    end)

    it("should calculate partial score for mixed results", function()
        local Signature = require("dslua.core.signature")
        local Field = require("dslua.core.field")
        local Predict = require("dslua.modules.predict")

        local sig = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local module = Predict.new(sig)
        local dataset = {
            {input = {question = "2+2"}, output = {answer = "4"}},
            {input = {question = "3+3"}, output = {answer = "6"}}
        }

        local optimizer = BaseOptimizer.new(module, {
            dataset = dataset,
            metric = function(result, expected)
                return result.answer == expected.answer and 1 or 0
            end
        })

        -- Mock LLM that gets both wrong
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {answer = "wrong"}
            end
        }

        local ctx = require("dslua.core.context").new({llm = mock_llm})

        local score = optimizer:Evaluate(ctx, module)

        assert.is.equal(0.0, score) -- Both wrong
    end)
end)
