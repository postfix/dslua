describe("Field", function()
    it("should create field with name", function()
        local Field = require("dslua.core.field")
        local field = Field.new("question")

        assert.is.equal("question", field:Name())
        assert.is.equal("", field:Description())
    end)

    it("should create field with name and description", function()
        local Field = require("dslua.core.field")
        local field = Field.new("question", {desc = "The question to answer"})

        assert.is.equal("question", field:Name())
        assert.is.equal("The question to answer", field:Description())
    end)

    it("should support fluent description setting", function()
        local Field = require("dslua.core.field")
        local field = Field.new("question"):WithDescription("Test desc")

        assert.is.equal("Test desc", field:Description())
        assert.is.equal(field, field:WithDescription("Test"))  -- Returns self
    end)
end)
