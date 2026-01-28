local Field = {}
Field.__index = Field

function Field.new(name, opts)
    opts = opts or {}
    local self = {
        _name = name,
        _description = opts.desc or "",
    }
    return setmetatable(self, Field)
end

function Field:Name()
    return self._name
end

function Field:Description()
    return self._description
end

function Field:WithDescription(desc)
    self._description = desc
    return self
end

return Field
