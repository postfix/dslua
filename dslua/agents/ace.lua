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
    local state = {
        original_input = input.question or input,  -- Store for REASON action
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

    return state
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

function ACE:_FindMatchingRules(state, rules)
    local matches = {}

    for _, rule in ipairs(rules) do
        if self:_RuleMatches(rule, state) then
            table.insert(matches, rule)
        end
    end

    return matches
end

function ACE:_RuleMatches(rule, state)
    for feature_name, condition in pairs(rule.conditions) do
        if not self:_ConditionMatches(condition, state, feature_name) then
            return false
        end
    end
    return true
end

function ACE:_ConditionMatches(condition, state, feature_name)
    -- Find feature value in state (search across task, self, history)
    local feature_value = self:_GetFeatureValue(state, feature_name)
    if feature_value == nil then
        return false
    end

    local op = condition.op
    local threshold = condition.threshold
    local value = condition.value

    if op == "==" then
        return feature_value == value
    elseif op == ">" then
        return feature_value > threshold
    elseif op == "<" then
        return feature_value < threshold
    elseif op == ">=" then
        return feature_value >= threshold
    elseif op == "<=" then
        return feature_value <= threshold
    else
        return false
    end
end

function ACE:_GetFeatureValue(state, feature_name)
    -- Search in task layer
    if state.task[feature_name] ~= nil then
        return state.task[feature_name]
    end

    -- Search in self layer
    if state.self[feature_name] ~= nil then
        return state.self[feature_name]
    end

    -- Search in history layer (for historical success rates)
    if state.history[feature_name] ~= nil then
        return state.history[feature_name]
    end

    return nil
end

function ACE:_ScoreRules(rules, state)
    local scores = {}

    for _, rule in ipairs(rules) do
        local salience = self:_ComputeSalience(rule, state)
        scores[rule] = rule.weight * salience
    end

    return scores
end

function ACE:_ComputeSalience(rule, state)
    -- Simple salience: how strongly conditions are satisfied
    -- For now, use a constant; can be enhanced later
    return 1.0
end

function ACE:_SelectAction(state, rules)
    if #rules == 0 then
        return "REASON"  -- Fallback action
    end

    local scores = self:_ScoreRules(rules, state)

    -- Find highest score
    local best_rule = nil
    local best_score = -1

    for _, rule in ipairs(rules) do
        if scores[rule] and scores[rule] > best_score then
            best_score = scores[rule]
            best_rule = rule
        elseif scores[rule] and scores[rule] == best_score then
            -- Tie-break by higher ID (more recent)
            if rule.id > best_rule.id then
                best_rule = rule
            end
        end
    end

    return best_rule.action
end

function ACE:_DecideWithLogging(state, rules)
    local matches = self:_FindMatchingRules(state, rules)
    local action = self:_SelectAction(state, matches)

    -- Collect competing actions for logging
    local competing = {}
    for _, rule in ipairs(matches) do
        if rule.action ~= action then
            table.insert(competing, {
                action = rule.action,
                score = self:_ScoreRules({rule}, state)[rule]
            })
        end
    end

    return {
        action = action,
        competing_actions = competing,
        state_snapshot = self:_ShallowCopy(state)
    }
end

function ACE:_ShallowCopy(obj)
    local copy = {}
    for k, v in pairs(obj) do
        if type(v) == "table" then
            copy[k] = "[TABLE]"  -- Don't deep copy for logging
        else
            copy[k] = v
        end
    end
    return copy
end

function ACE:Execute(ctx, input, opts)
    opts = opts or {}
    local state = self:_InitializeState(input)

    while state.self.steps_taken < state.self.max_steps_limit do
        -- Decide next action
        local decision = self:_DecideWithLogging(state, self._rules)
        local action = decision.action

        -- Log decision if enabled
        if self._config.log_decisions then
            self:_LogDecision(state, decision)
        end

        -- Execute action
        local action_result = self:_ExecuteAction(ctx, state, action)

        -- Update state
        state.self.current_action = action
        table.insert(state.self.action_history, action)
        state.self.steps_taken = state.self.steps_taken + 1

        -- Update confidence if action returned it
        if action_result.confidence then
            state.self.confidence = action_result.confidence
            table.insert(state.self.confidence_trajectory, action_result.confidence)
        end

        -- Check if we have a final answer
        if action_result.answer then
            state.answer = action_result.answer
        end

        -- Check for termination (after execution)
        if action == "TERMINATE" then
            return self:_FormatResult(state, "SUCCESS")
        end

        -- If REASON action produced an answer, we're done
        if action == "REASON" and action_result.answer then
            return self:_FormatResult(state, "SUCCESS")
        end
    end

    -- Timeout
    return self:_FormatResult(state, "TIMEOUT")
end

function ACE:_ExecuteAction(ctx, state, action)
    local result = nil

    if action == "REASON" then
        -- Delegate to wrapped module
        local input = {question = state.original_input or state.task.input}
        local response = self._module:Process(ctx, input)

        -- Parse response to extract answer
        -- If response is a table with content, parse it
        if type(response) == "table" and response.content then
            result = self:_ParseLLMResponse(response.content)
        else
            result = response
        end
    elseif action == "DECOMPOSE" then
        -- For now, just delegate to REASON
        -- TODO: Implement actual decomposition
        return self:_ExecuteAction(ctx, state, "REASON")
    elseif action == "RETRIEVE" then
        -- For now, just delegate to REASON
        -- TODO: Implement tool delegation
        return self:_ExecuteAction(ctx, state, "REASON")
    elseif action == "SYNTHESIZE" then
        -- For now, just delegate to REASON
        return self:_ExecuteAction(ctx, state, "REASON")
    elseif action == "VERIFY" then
        -- For now, just delegate to REASON
        return self:_ExecuteAction(ctx, state, "REASON")
    else
        -- Unknown action, fallback to REASON
        return self:_ExecuteAction(ctx, state, "REASON")
    end

    return result or {}
end

function ACE:_ParseLLMResponse(content)
    -- Try to extract answer from content
    -- Look for patterns like "Answer: <value>" or just return the content
    local answer = content:match("Answer:%s*(.+)")

    if answer then
        return {answer = answer, content = content}
    else
        -- No pattern found, return content as answer
        return {answer = content, content = content}
    end
end

function ACE:_LogDecision(state, decision)
    -- TODO: Implement decision logging
    -- For now, just store in memory
    if not self._decision_log then
        self._decision_log = {}
    end
    table.insert(self._decision_log, {
        step = state.self.steps_taken,
        action = decision.action,
        competing = decision.competing_actions
    })
end

function ACE:_FormatResult(state, termination_reason)
    local result = {
        answer = state.answer,
        stats = {
            steps_taken = state.self.steps_taken,
            action_history = state.self.action_history,
            confidence = state.self.confidence
        },
        termination_reason = termination_reason
    }

    return result
end

return ACE
