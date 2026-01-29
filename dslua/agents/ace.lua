local BaseAgent = require("dslua.agents.base")

local ACE = {}
ACE.__index = ACE
setmetatable(ACE, {__index = BaseAgent})

function ACE.new(module, opts)
    opts = opts or {}
    local self = BaseAgent.new(module:Signature(), opts)
    setmetatable(self, ACE)

    self._module = module
    self._rules = opts.rules or {}
    self._config = {
        learning_mode = opts.learning_mode or "passive",
        max_steps = opts.max_steps or 10,
        log_decisions = opts.log_decisions or false
    }

    -- Initialize history storage
    self._history = {
        success_rate = {},
        tool_effectiveness = {},
        failure_patterns = {},
        total_executions = 0,
        termination_reasons = {success = 0, timeout = 0, error = 0}
    }

    return self
end

function ACE:_Module()
    return self._module
end

function ACE:_InitializeState(input)
    return {
        -- Layer 1: Task Features (Objective, Static)
        task = self:_ExtractTaskFeatures(input),

        -- Layer 2: Self-Monitoring (Dynamic, Per-Step)
        self = {
            confidence = 0.5,
            confidence_trajectory = {},
            uncertainty_markers = {},
            current_action = nil,
            action_history = {},
            steps_taken = 0,
            max_steps_limit = self._config.max_steps,
            tool_failures = {},
            tool_success_rate = {}
        },

        -- Layer 3: Performance History (Learned, Slow-Moving)
        history = self._history
    }
end

function ACE:_ExtractTaskFeatures(input)
    local question = input.question or ""
    local question_lower = string.lower(question)

    -- Normalize features to [0,1]
    local length = math.min(#question / 1000, 1.0)  -- rough normalization

    -- Simple heuristic for entity count (count capitalized words)
    local entities = 0
    for word in string.gmatch(question, "%u%w*") do
        entities = entities + 1
    end
    local entity_count = math.min(entities / 10, 1.0)

    -- Task type detection (simple keyword matching)
    local task_type = "general"
    if question_lower:match("calculat") or question_lower:match("%d+%s*[%+%-*/%s]%s*%d") then
        task_type = "math"
    elseif question_lower:match("what is") or question_lower:match("who is") or question_lower:match("where is") then
        task_type = "factual"
    elseif question_lower:match("write") or question_lower:match("code") or question_lower:match("function") then
        task_type = "code"
    end

    -- Complexity estimate (simple heuristic)
    local complexity = (length + entity_count) / 2
    complexity = math.min(math.max(complexity, 0), 1)

    -- Tool requirement hints
    local tool_requirements = {}
    if task_type == "math" then
        table.insert(tool_requirements, "calculator")
    elseif task_type == "factual" then
        table.insert(tool_requirements, "search")
    end

    return {
        input_length = length,
        entity_count = entity_count,
        task_type = task_type,
        complexity_estimate = complexity,
        tool_requirements = tool_requirements,
        estimated_steps = math.ceil(complexity * 5) + 1
    }
end

return ACE
