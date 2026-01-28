local Module = require("dslua.modules.base")

local FewShot = {}
FewShot.__index = FewShot
setmetatable(FewShot, {__index = Module})

function FewShot.new(base_module, demonstrations)
    local self = Module.new(base_module:Signature())
    setmetatable(self, FewShot)

    self._base = base_module
    self._demonstrations = demonstrations or {}

    return self
end

function FewShot:Process(ctx, input)
    local llm = ctx:LLM() or self:LLM()
    if not llm then
        error("LLM not configured")
    end

    local prompt = self:_buildPrompt(input)
    local response = llm:Complete(ctx, prompt)

    -- If response is already a table with fields, return it directly
    if type(response) == "table" and next(response) ~= nil then
        local has_string_keys = false
        for k, v in pairs(response) do
            if type(k) == "string" then
                has_string_keys = true
                break
            end
        end
        if has_string_keys then
            return response
        end
    end

    -- Otherwise parse as string content
    local content = response.content or response
    if type(content) == "string" then
        return self:_parseOutput(content)
    end

    return response
end

function FewShot:_buildPrompt(input)
    local parts = {}

    -- Add demonstrations
    for _, demo in ipairs(self._demonstrations) do
        table.insert(parts, self:_formatDemo(demo))
    end

    -- Add current input
    table.insert(parts, self:_formatInput(input))

    return table.concat(parts, "\n\n")
end

function FewShot:_formatDemo(demo)
    local input_str = self:_formatInput(demo.input)
    local output_str = self:_formatOutput(demo.output)
    return input_str .. "\n" .. output_str
end

function FewShot:_formatInput(input)
    local parts = {}
    for field_name, field_value in pairs(input) do
        table.insert(parts, string.format("%s: %s", field_name, tostring(field_value)))
    end
    return table.concat(parts, "\n")
end

function FewShot:_formatOutput(output)
    local parts = {}
    for field_name, field_value in pairs(output) do
        table.insert(parts, string.format("%s: %s", field_name, tostring(field_value)))
    end
    return table.concat(parts, "\n")
end

function FewShot:_parseOutput(content)
    -- Simple parsing: extract field values from "field: value" lines
    local result = {}
    for line in content:gmatch("[^\n]+") do
        local field, value = line:match("^(%w+):%s*(.+)$")
        if field then
            result[field] = value
        end
    end
    return result
end

return FewShot
