local Tool = {}
Tool.__index = Tool

function Tool.new(name, config)
    return setmetatable({
        _name = name,
        _description = config.description,
        _func = config.func,
    }, Tool)
end

function Tool:Execute(args)
    return self._func(args)
end

function Tool:Name()
    return self._name
end

function Tool:Description()
    return self._description
end

return Tool
