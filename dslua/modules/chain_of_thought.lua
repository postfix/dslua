local Predict = require("dslua.modules.predict")

local ChainOfThought = {}
ChainOfThought.__index = ChainOfThought
setmetatable(ChainOfThought, {__index = Predict})

function ChainOfThought.new(signature)
    local self = Predict.new(signature)
    setmetatable(self, ChainOfThought)
    return self
end

function ChainOfThought:Process(ctx, input)
    local llm = ctx:LLM() or self:LLM()
    local prompt = self:_buildCOTPrompt(input)
    local response = llm:Complete(ctx, prompt)
    return self:_parseOutput(response)
end

function ChainOfThought:_buildCOTPrompt(input)
    local template = [[
Think step-by-step to answer the following question.

%s

Reasoning: Let's think through this step by step.
Answer:]]

    local input_text = self:_formatInputs(input)
    return string.format(template, input_text)
end

function ChainOfThought:_parseOutput(response)
    local content = response.content

    -- Try to extract structured reasoning and answer
    local reasoning = content:match("Reasoning:%s*(.-)%s*Answer:") or ""
    local answer = content:match("Answer:%s*(.+)") or content

    return {
        reasoning = reasoning,
        answer = answer,
        raw = content,
    }
end

return ChainOfThought
