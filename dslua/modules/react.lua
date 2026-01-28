local ChainOfThought = require("dslua.modules.chain_of_thought")

local ReAct = {}
ReAct.__index = ReAct
setmetatable(ReAct, {__index = ChainOfThought})

function ReAct.new(signature, opts)
    opts = opts or {}
    local self = ChainOfThought.new(signature)
    setmetatable(self, ReAct)
    self._tools = opts.tools or {}
    self._maxIterations = opts.max_iterations or 10
    return self
end

function ReAct:Process(ctx, input)
    local llm = ctx:LLM() or self:LLM()
    local state = {
        thoughts = {},
        actions = {},
        observations = {},
        input = input,
    }

    for i = 1, self._maxIterations do
        -- Generate thought and action
        local prompt = self:_buildReActPrompt(state, i)
        local response = llm:Complete(ctx, prompt)
        local step = self:_parseStep(response.content)

        table.insert(state.thoughts, step.thought)

        if step.action == "finish" then
            state.answer = step.answer
            break
        end

        -- Execute tool
        local tool = self:_findTool(step.action)
        local observation = tool:Execute(step.args)
        table.insert(state.observations, observation)
        table.insert(state.actions, {action = step.action, args = step.args})
    end

    return self:_formatOutput(state)
end

function ReAct:_buildReActPrompt(state, iteration)
    local template = [[
Question: %s

%s

Thought %d:]]

    local history = self:_formatHistory(state)
    local question = self:_formatInputs(state.input)

    return string.format(template, question, history, iteration)
end

function ReAct:_formatHistory(state)
    local parts = {}
    for i, obs in ipairs(state.observations) do
        table.insert(parts, string.format("Observation %d: %s", i, tostring(obs)))
    end
    return table.concat(parts, "\n")
end

function ReAct:_findTool(name)
    for _, tool in ipairs(self._tools) do
        if tool:Name() == name then
            return tool
        end
    end
    error("Tool not found: " .. name)
end

function ReAct:_parseStep(content)
    -- Parse: Thought: ... Action: tool_name[args] or finish[answer]
    local thought = content:match("Thought:%s*(.-)\n") or ""

    local action_match = content:match("Action:%s*(.-)\n")
    if not action_match then
        action_match = content:match("Action:%s*(.+)$") or ""
    end

    local action, args = action_match:match("^(.+)%[(.+)%]$")

    if not action then
        action = "finish"
        args = content:match("Answer:%s*(.+)") or content
    end

    if action == "finish" then
        return {thought = thought, action = "finish", answer = args}
    end

    return {
        thought = thought,
        action = action,
        args = args,
    }
end

function ReAct:_formatOutput(state)
    return {
        answer = state.answer,
        thoughts = state.thoughts,
        actions = state.actions,
        observations = state.observations,
        iterations = #state.thoughts,
    }
end

return ReAct
