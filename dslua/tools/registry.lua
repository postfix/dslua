local Registry = {}
Registry.__index = Registry

function Registry.new()
    return setmetatable({
        _tools = {},
        _metadata = {},
    }, Registry)
end

function Registry:Register(name, tool, metadata)
    if self._tools[name] then
        error(string.format("Tool '%s' is already registered", name))
    end

    self._tools[name] = tool
    self._metadata[name] = metadata or {}
end

function Registry:Get(name)
    if not self._tools[name] then
        error(string.format("Tool '%s' not found in registry", name))
    end
    return self._tools[name]
end

function Registry:Has(name)
    return self._tools[name] ~= nil
end

function Registry:List(category)
    if category then
        local results = {}
        for name, meta in pairs(self._metadata) do
            if meta.category == category then
                table.insert(results, {
                    name = name,
                    tool = self._tools[name],
                    metadata = meta
                })
            end
        end
        return results
    else
        local results = {}
        for name, tool in pairs(self._tools) do
            table.insert(results, {
                name = name,
                tool = tool,
                metadata = self._metadata[name]
            })
        end
        return results
    end
end

function Registry:GetMetadata(name)
    if not self._tools[name] then
        error(string.format("Tool '%s' not found in registry", name))
    end
    return self._metadata[name]
end

return Registry
