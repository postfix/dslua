local Predict = require("dslua.modules.predict")

local Refine = {}
Refine.__index = Refine
setmetatable(Refine, {__index = Predict})

function Refine.new(signature, opts)
    opts = opts or {}
    local self = Predict.new(signature)
    setmetatable(self, Refine)
    self._maxIterations = opts.max_iterations or 3
    return self
end

function Refine:Process(ctx, input)
    local llm = ctx:LLM() or self:LLM()
    local current = {content = ""}

    for i = 1, self._maxIterations do
        local prompt = self:_buildRefinePrompt(input, current, i)
        local response = llm:Complete(ctx, prompt)

        if i == 1 then
            current = response
        else
            -- Extract refined answer
            local refined = response.content:match("Refined answer:%s*(.*)")
            current.content = refined or response.content
        end
    end

    return {
        answer = current.content,
        iterations = self._maxIterations
    }
end

function Refine:_buildRefinePrompt(input, previous, iteration)
    if iteration == 1 then
        return string.format("%s\n\nAnswer:", self:_formatInputs(input))
    end

    return string.format([[Original question: %s

Previous answer: %s

Please critique and improve this answer. Focus on:
1. Accuracy - Is the information correct?
2. Completeness - Is anything important missing?
3. Clarity - Is the answer well-structured and easy to understand?

Refined answer:]],
        self:_formatInputs(input),
        previous.content
    )
end

return Refine
