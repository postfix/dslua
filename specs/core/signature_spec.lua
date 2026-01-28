describe("Signature", function()
    local Field = require("dslua.core.field")

    it("should create signature with input and output fields", function()
        local Signature = require("dslua.core.signature")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        assert.is.equal(1, #signature:InputFields())
        assert.is.equal("question", signature:InputFields()[1]:Name())
        assert.is.equal(1, #signature:OutputFields())
        assert.is.equal("answer", signature:OutputFields()[1]:Name())
    end)

    it("should support multiple input and output fields", function()
        local Signature = require("dslua.core.signature")
        local signature = Signature.new(
            {Field.new("question"), Field.new("context")},
            {Field.new("answer"), Field.new("confidence")}
        )

        assert.is.equal(2, #signature:InputFields())
        assert.is.equal(2, #signature:OutputFields())
    end)

    it("should support instruction setting", function()
        local Signature = require("dslua.core.signature")
        local signature = Signature.new({}, {}):WithInstruction("Be concise")

        assert.is.equal("Be concise", signature:Instruction())
    end)

    it("should return self for fluent chaining", function()
        local Signature = require("dslua.core.signature")
        local signature = Signature.new({}, {})
        local result = signature:WithInstruction("Test")

        assert.is.equal(signature, result)
    end)
end)
