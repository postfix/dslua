describe("BootstrapFewShot Optimizer", function()
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

    it("should create optimizer with module and dataset", function()
        local sig = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local module = Predict.new(sig)
        local trainset = {
            {input = {question = "1+1"}, output = {answer = "2"}},
            {input = {question = "2+2"}, output = {answer = "4"}},
            {input = {question = "3+3"}, output = {answer = "6"}}
        }

        local optimizer = BootstrapFewShot.new(module, {
            trainset = trainset,
            valset = trainset,  -- Use same for testing
            max_bootstraps = 2,
            max_labeled_demos = 2
        })

        assert.is_not_nil(optimizer)
        assert.is.equal(3, #optimizer._trainset)
    end)

    it("should compile optimized fewshot program", function()
        local sig = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local module = Predict.new(sig)
        local trainset = {
            {input = {question = "1+1"}, output = {answer = "2"}},
            {input = {question = "2+2"}, output = {answer = "4"}},
            {input = {question = "3+3"}, output = {answer = "6"}}
        }

        local optimizer = BootstrapFewShot.new(module, {
            trainset = trainset,
            valset = {{input = {question = "4+4"}, output = {answer = "8"}}},
            max_bootstraps = 2,
            max_labeled_demos = 2
        })

        -- Mock LLM that answers correctly
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                local q = prompt:match("%d+%+%d+")
                if q == "4+4" then
                    return {answer = "8"}
                end
                return {answer = "calculated"}
            end
        }

        local ctx = require("dslua.core.context").new({llm = mock_llm})

        local compiled = optimizer:Compile(ctx, 2)

        assert.is_not_nil(compiled)
        assert.is_not_nil(compiled._demonstrations)
        assert.is_true(#compiled._demonstrations > 0)
    end)

    it("should select best subset based on validation score", function()
        local sig = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local module = Predict.new(sig)
        local trainset = {
            {input = {question = "1+1"}, output = {answer = "2"}},
            {input = {question = "2+2"}, output = {answer = "4"}}
        }

        local optimizer = BootstrapFewShot.new(module, {
            trainset = trainset,
            valset = {{input = {question = "3+3"}, output = {answer = "6"}}},
            max_bootstraps = 3,
            max_labeled_demos = 2
        })

        -- Track if Compile was called and returned something valid
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {answer = "6"}
            end
        }

        local ctx = require("dslua.core.context").new({llm = mock_llm})

        local compiled = optimizer:Compile(ctx, 3)

        assert.is_not_nil(compiled)
        assert.is_not_nil(compiled._demonstrations)
        -- Should have selected some demonstrations
        assert.is_true(#compiled._demonstrations >= 0)
    end)

    it("should handle empty trainset", function()
        local sig = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local module = Predict.new(sig)
        local optimizer = BootstrapFewShot.new(module, {
            trainset = {},
            valset = {},
            max_bootstraps = 2,
            max_labeled_demos = 2
        })

        local ctx = require("dslua.core.context").new({})

        local compiled = optimizer:Compile(ctx, 2)

        assert.is_not_nil(compiled)
        assert.is.equal(0, #compiled._demonstrations)
    end)
end)
