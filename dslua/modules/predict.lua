local Base = require("dslua.modules.base")
local Predict = {}
Predict.__index = Predict
setmetatable(Predict, {__index = Base})

function Predict.new(signature)
    local self = Base.new(signature)
    setmetatable(self, Predict)
    return self
end

function Predict:Process(ctx, input)
    local llm = ctx:LLM() or self:LLM()
    if not llm then
        error("No LLM configured in module or context")
    end

    local prompt = self:_buildPrompt(input)
    local response = llm:Complete(ctx, prompt, {})

    return response
end

function Predict:_buildPrompt(input)
    local parts = {}

    for _, field in ipairs(self._signature:InputFields()) do
        local value = input[field:Name()]
        if value then
            table.insert(parts, string.format("%s: %s", field:Name(), tostring(value)))
        end
    end

    return table.concat(parts, "\n")
end

function Predict:_formatInputs(input)
    local parts = {}

    for _, field in ipairs(self._signature:InputFields()) do
        local value = input[field:Name()]
        if value then
            table.insert(parts, string.format("%s: %s", field:Name(), tostring(value)))
        end
    end

    return table.concat(parts, "\n")
end

return Predict
