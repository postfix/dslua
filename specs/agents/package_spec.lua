describe("ACE Package Exports", function()
    it("should export ACE from agents package", function()
        local agents = require("dslua.agents")
        assert.is_not_nil(agents.ACE)
    end)

    it("should export ACE rules", function()
        local agents = require("dslua.agents")
        assert.is_not_nil(agents.ACERules)
    end)

    it("should export ACE from main dslua package", function()
        local dslua = require("dslua")
        assert.is_not_nil(dslua.ACE)
    end)

    it("should create ACE using main package", function()
        local dslua = require("dslua")

        local signature = dslua.Signature.new(
            {dslua.Field.new("question")},
            {dslua.Field.new("answer")}
        )
        local module = dslua.Predict.new(signature)

        local ace = dslua.ACE.new(module, {
            rules = dslua.ACERules
        })

        assert.is_not_nil(ace)
    end)
end)
