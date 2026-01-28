describe("Context", function()
    it("should create context with no options", function()
        local Context = require("dslua.core.context")
        local ctx = Context.new()

        assert.is.equal(nil, ctx:LLM())
        assert.is.equal(0, #ctx:Trace())
    end)

    it("should create context with LLM", function()
        local Context = require("dslua.core.context")
        local mock_llm = {name = "test"}
        local ctx = Context.new({llm = mock_llm})

        assert.is.equal(mock_llm, ctx:LLM())
    end)

    it("should support creating derived context with LLM", function()
        local Context = require("dslua.core.context")
        local ctx1 = Context.new()
        local mock_llm = {name = "test"}
        local ctx2 = ctx1:WithLLM(mock_llm)

        assert.is.equal(nil, ctx1:LLM())
        assert.is.equal(mock_llm, ctx2:LLM())
        assert.is.not_equal(ctx1, ctx2)  -- New context created
    end)

    it("should store trace entries", function()
        local Context = require("dslua.core.context")
        local ctx = Context.new()
        ctx:AddTrace({step = "test", data = "value"})

        assert.is.equal(1, #ctx:Trace())
        assert.is.equal("test", ctx:Trace()[1].step)
    end)
end)
