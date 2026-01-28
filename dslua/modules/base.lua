local Module = {}
Module.__index = Module

function Module.new(signature)
    local self = {
        _signature = signature,
        _llm = nil,
        _config = {},
    }
    return setmetatable(self, Module)
end

function Module:Signature()
    return self._signature
end

function Module:LLM()
    return self._llm
end

function Module:WithLLM(llm)
    self._llm = llm
    return self
end

function Module:Process(ctx, input)
    error("Process() must be implemented by subclass")
end

function Module:Forward(ctx, input)
    return self:Process(ctx, input)
end

return Module
