describe("ReAct", function()
    local Field = require("dslua.core.field")
    local Signature = require("dslua.core.signature")
    local Context = require("dslua.core.context")
    local Tool = require("dslua.tools.base")

    it("should create ReAct with signature and tools", function()
        local ReAct = require("dslua.modules.react")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local tools = {
            Tool.new("search", {
                description = "Search the web",
                func = function(args) return {result = "found"} end
            })
        }
        local react = ReAct.new(signature, {tools = tools})

        assert.is.equal(signature, react:Signature())
        assert.is.equal(1, #react._tools)
    end)

    it("should build ReAct prompt with history", function()
        local ReAct = require("dslua.modules.react")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local react = ReAct.new(signature, {tools = {}})

        local state = {
            input = {question = "What is the capital of France?"},
            observations = {"Paris is the capital."},
            thoughts = {},
        }

        local prompt = react:_buildReActPrompt(state, 2)

        assert.is_not_nil(string.find(prompt, "What is the capital", 1, true))
        assert.is_not_nil(string.find(prompt, "Paris", 1, true))
        assert.is_not_nil(string.find(prompt, "Thought 2:", 1, true))
    end)

    it("should parse ReAct step with action", function()
        local ReAct = require("dslua.modules.react")
        local signature = Signature.new({}, {})
        local react = ReAct.new(signature, {tools = {}})

        local content = "Thought: I need to search.\nAction: search[Paris]"
        local step = react:_parseStep(content)

        assert.is.equal("I need to search.", step.thought)
        assert.is.equal("search", step.action)
    end)

    it("should execute single turn and finish", function()
        local ReAct = require("dslua.modules.react")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Thought: The answer is 42\nAction: finish[42]"}
            end
        }

        local react = ReAct.new(signature, {tools = {}})
        local ctx = Context.new({llm = mock_llm})

        local result = react:Process(ctx, {question = "What is 6*7?"})

        assert.is.equal("42", result.answer)
        assert.is.equal(1, result.iterations)
    end)
end)
