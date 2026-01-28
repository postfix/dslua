local Tool = require("dslua.tools.base")

local Calculator = {}
Calculator.__index = Calculator

function Calculator.new()
    local self = setmetatable({}, Calculator)

    self._operations = {
        add = function(a, b) return a + b end,
        subtract = function(a, b) return a - b end,
        multiply = function(a, b) return a * b end,
        divide = function(a, b)
            if b == 0 then
                error("Division by zero")
            end
            return a / b
        end
    }

    return self
end

function Calculator:Execute(args)
    local operation = args.operation
    local a = tonumber(args.a)
    local b = tonumber(args.b)

    if not operation or not a or not b then
        error("Calculator requires 'operation', 'a', and 'b' parameters")
    end

    local func = self._operations[operation]
    if not func then
        error(string.format("Unknown operation: %s", operation))
    end

    return func(a, b)
end

function Calculator:Name()
    return "calculator"
end

function Calculator:Description()
    return "Performs arithmetic operations: add, subtract, multiply, divide"
end

return Calculator
