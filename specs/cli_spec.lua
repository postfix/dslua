describe("CLI", function()
    it("should load without errors", function()
        local cli = require("cli.dslua")

        assert.is_not_nil(cli)
        assert.is_true(type(cli.run) == "function")
    end)
end)
