local Signature = {}
Signature.__index = Signature

function Signature.new(inputs, outputs)
    local self = {
        _inputs = inputs,
        _outputs = outputs,
        _instruction = "",
    }
    return setmetatable(self, Signature)
end

function Signature:InputFields()
    return self._inputs
end

function Signature:OutputFields()
    return self._outputs
end

function Signature:Instruction()
    return self._instruction
end

function Signature:WithInstruction(instruction)
    self._instruction = instruction
    return self
end

return Signature
