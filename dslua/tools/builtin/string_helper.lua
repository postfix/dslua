local Tool = require("dslua.tools.base")

local StringHelper = {}
StringHelper.__index = StringHelper

function StringHelper.new()
    return setmetatable({}, StringHelper)
end

function StringHelper:Execute(args)
    local operation = args.operation
    local text = args.text

    if not operation or not text then
        error("StringHelper requires 'operation' and 'text' parameters")
    end

    if operation == "length" then
        return #text
    elseif operation == "uppercase" then
        return string.upper(text)
    elseif operation == "lowercase" then
        return string.lower(text)
    elseif operation == "trim" then
        return text:match("^%s*(.-)%s*$")
    elseif operation == "reverse" then
        return text:reverse()
    else
        error(string.format("Unknown operation: %s", operation))
    end
end

function StringHelper:Name()
    return "string_helper"
end

function StringHelper:Description()
    return "Performs string operations: length, uppercase, lowercase, trim, reverse"
end

return StringHelper
