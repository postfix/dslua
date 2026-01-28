describe("Tool", function()
    it("should create tool with name and function", function()
        local Tool = require("dslua.tools.base")
        local tool = Tool.new("test", {
            description = "A test tool",
            func = function(args)
                return {result = "success"}
            end
        })

        assert.is.equal("test", tool:Name())
        assert.is.equal("A test tool", tool:Description())
    end)

    it("should execute tool function", function()
        local Tool = require("dslua.tools.base")
        local tool = Tool.new("calculator", {
            description = "Calculate expression",
            func = function(args)
                return {result = args.a + args.b}
            end
        })

        local result = tool:Execute({a = 2, b = 3})

        assert.is.equal(5, result.result)
    end)

    it("should pass args to function", function()
        local Tool = require("dslua.tools.base")
        local received_args = nil

        local tool = Tool.new("args_test", {
            description = "Test args passing",
            func = function(args)
                received_args = args
                return {}
            end
        })

        tool:Execute({test = "value", number = 42})

        assert.is.equal("value", received_args.test)
        assert.is.equal(42, received_args.number)
    end)
end)
