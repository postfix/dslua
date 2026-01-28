describe("Module", function()
    local Field = require("dslua.core.field")
    local Signature = require("dslua.core.signature")

    it("should create module with signature", function()
        local Module = require("dslua.modules.base")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local module = Module.new(signature)

        assert.is.equal(signature, module:Signature())
    end)

    it("should support setting LLM", function()
        local Module = require("dslua.modules.base")
        local signature = Signature.new({}, {})
        local module = Module.new(signature)
        local mock_llm = {name = "test"}

        module:WithLLM(mock_llm)

        assert.is.equal(mock_llm, module:LLM())
    end)

    it("should return self for fluent chaining", function()
        local Module = require("dslua.modules.base")
        local signature = Signature.new({}, {})
        local module = Module.new(signature)
        local mock_llm = {name = "test"}

        local result = module:WithLLM(mock_llm)

        assert.is.equal(module, result)
    end)

    it("should error on Process() if not overridden", function()
        local Module = require("dslua.modules.base")
        local signature = Signature.new({}, {})
        local module = Module.new(signature)
        local ctx = require("dslua.core.context").new()

        assert.has_error(function()
            module:Process(ctx, {})
        end, "Process() must be implemented by subclass")
    end)
end)
