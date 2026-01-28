local BaseAgent = require("dslua.agents.base")
local ReAct = require("dslua.modules.react")

local ReActAgent = {}
ReActAgent.__index = ReActAgent
setmetatable(ReActAgent, {__index = BaseAgent})

function ReActAgent.new(signature, opts)
    opts = opts or {}
    local self = BaseAgent.new(signature, opts)
    setmetatable(self, ReActAgent)

    self._tool_registry = opts.tool_registry
    self._tools = {}
    self._llm = nil

    return self
end

function ReActAgent:WithLLM(llm)
    self._llm = llm
    return self
end

function ReActAgent:_initialize(input, opts)
    local tools_list = self:_loadTools()

    local state = {
        steps = {},
        summary = "",
        current_iteration = 1,
        tool_usage = {},
        errors = {},
        input = input,
        tools = tools_list,
        answer = nil
    }

    return state
end

function ReActAgent:_loadTools()
    if not self._tool_registry then
        return {}
    end

    local all_tools = self._tool_registry:List()
    local loaded = {}

    for _, tool_info in ipairs(all_tools) do
        table.insert(loaded, tool_info.tool)
    end

    self._tools = loaded
    return loaded
end

function ReActAgent:_shouldStop(state)
    return state.answer ~= nil
end

function ReActAgent:_executeStep(ctx, state)
    local llm = ctx:LLM() or self._llm
    if not llm then
        error("LLM not configured")
    end

    local react_module = ReAct.new(self._signature, {
        tools = self._tools,
        max_iterations = 1
    })

    local prompt = self:_buildReActPrompt(state)

    local response = llm:Complete(ctx, prompt)
    local step = self:_parseStep(response.content)

    table.insert(state.steps, {
        iteration = state.current_iteration,
        thought = step.thought or "",
        action = step.action or "",
        args = step.args or "",
        observation = nil,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    })

    if step.action == "finish" then
        state.answer = step.answer or step.args
        return {stop = true}
    end

    local observation, err = self:_executeTool(step.action, step.args, state)
    state.steps[state.current_iteration].observation = observation

    if err then
        table.insert(state.errors, {
            tool = step.action,
            error = tostring(err),
            retries = 0,
            recovered = false,
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        })
    end

    self:_updateSummary(state, state.steps[state.current_iteration])

    return nil
end

function ReActAgent:_buildReActPrompt(state)
    local template = [[
Question: %s

Conversation so far: %s

Available tools: %s

Thought %d:]]

    local question = tostring(state.input)
    local summary = state.summary or "No previous conversation."
    local tools_desc = self:_formatTools()

    return string.format(template, question, summary, tools_desc, state.current_iteration)
end

function ReActAgent:_formatTools()
    if not self._tool_registry then
        return "No tools available"
    end

    local all_tools = self._tool_registry:List()
    local descriptions = {}

    for _, tool_info in ipairs(all_tools) do
        local meta = tool_info.metadata or {}
        table.insert(descriptions, string.format("- %s: %s",
            tool_info.name,
            meta.description or tool_info.tool:Description() or "No description"))
    end

    return table.concat(descriptions, "\n")
end

function ReActAgent:_parseStep(content)
    local thought = content:match("Thought:%s*(.-)\n") or ""
    local action_match = content:match("Action:%s*(.-)\n") or content:match("Action:%s*(.+)$") or ""

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
        args = args
    }
end

function ReActAgent:_executeTool(action_name, args_str, state)
    if not self._tool_registry or not self._tool_registry:Has(action_name) then
        return nil, string.format("Tool not found: %s", action_name)
    end

    local tool = self._tool_registry:Get(action_name)

    if not state.tool_usage[action_name] then
        state.tool_usage[action_name] = 0
    end
    state.tool_usage[action_name] = state.tool_usage[action_name] + 1

    local args = self:_parseArgs(args_str)

    -- Use retry logic from BaseAgent
    local success, result = self:_executeWithRetry(nil, function()
        return tool:Execute(args)
    end)

    if success then
        return tostring(result)
    else
        return nil, result
    end
end

function ReActAgent:_parseArgs(args_str)
    local args = {}

    for key, val in string.gmatch(args_str, "(%w+)=([%w%p]+)") do
        local num = tonumber(val)
        if num then
            args[key] = num
        elseif val == "true" then
            args[key] = true
        elseif val == "false" then
            args[key] = false
        else
            args[key] = val
        end
    end

    return args
end

function ReActAgent:_updateSummary(state, step)
    local parts = {}

    if state.summary and state.summary ~= "" then
        table.insert(parts, state.summary)
    end

    table.insert(parts, string.format("Step %d: %s -> %s -> %s",
        step.iteration,
        step.thought or "No thought",
        step.action or "No action",
        step.observation or "No observation"))

    state.summary = table.concat(parts, "\n")
end

function ReActAgent:_formatSimple(state)
    return state.answer or "No answer generated"
end

function ReActAgent:_formatStructured(state)
    return {
        answer = state.answer or "No answer generated",
        reasoning = state.steps,
        tool_usage = state.tool_usage,
        iterations = #state.steps,
        summary = state.summary,
        error_history = state.errors
    }
end

return ReActAgent
