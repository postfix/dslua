local Context = {}
Context.__index = Context

function Context.new(opts)
    opts = opts or {}
    local self = {
        _llm = opts.llm or nil,
        _trace = opts.trace or {},
        _metadata = opts.metadata or {},
    }
    return setmetatable(self, Context)
end

function Context:LLM()
    return self._llm
end

function Context:WithLLM(llm)
    local ctx = Context.new({
        llm = llm,
        trace = self._trace,
        metadata = self._metadata,
    })
    return ctx
end

function Context:Trace()
    return self._trace
end

function Context:AddTrace(entry)
    table.insert(self._trace, entry)
end

return Context
