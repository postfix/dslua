local BaseAgent = require("dslua.agents.base")
local Decision = require("dslua.agents.ace_decision")

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

    -- Initialize weights table
    self._weights = {}
    for _, rule in ipairs(self._rules) do
        self._weights[rule.key] = rule.default_weight
    end

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
    -- Store original input for REASON action
    local original_question
    if type(input) == "table" then
        original_question = input.question
    else
        original_question = tostring(input)
    end

    local state = {
        original_input = original_question,
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
        input = input,  -- Store original input
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
        if Decision._RuleMatches(rule, state) then  -- Changed from self:_RuleMatches
            table.insert(matches, rule)
        end
    end

    return matches
end

-- Remove old _RuleMatches, _ConditionMatches, _GetFeatureValue methods
-- (Now in ace_decision.lua)

function ACE:_ScoreRules(rules, state)
    local scores = {}

    for _, rule in ipairs(rules) do
        local salience = self:_ComputeSalience(rule, state)
        local weight = self._weights[rule.key] or rule.default_weight
        scores[rule] = weight * salience
    end

    return scores
end

function ACE:_ComputeSalience(rule, state, opts)
    return Decision.ComputeSalience(rule, state, opts or {salience_mode = "binary"})
end

function ACE:LearnFromDemonstration(decision, opts)
    opts = opts or {}
    local learning = require("dslua.agents.ace_learning")

    -- Set defaults
    opts.learning_rate = opts.learning_rate or 0.05
    opts.max_weight_delta = opts.max_weight_delta or 0.02
    opts.min_margin = opts.min_margin or 0.05
    opts.epsilon = opts.epsilon or 0.01
    opts.salience_mode = opts.salience_mode or "binary"

    -- Initialize weights table if needed
    if not self._weights then
        self._weights = {}
        for _, rule in ipairs(self._rules) do
            self._weights[rule.key] = rule.default_weight
        end
    end

    return learning.LearnFromDemonstration(
        decision,
        self._rules,
        self._weights,
        opts,
        Decision.NormalizeState,
        {"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}
    )
end

function ACE:ExportLearnedWeights(filepath)
    local persistence = require("dslua.agents.ace_persistence")
    return persistence.ExportLearnedWeights(filepath, self._rules, self._weights)
end

function ACE:LoadWeightOverrides(filepath)
    local persistence = require("dslua.agents.ace_persistence")
    local overrides, err = persistence.LoadWeightOverrides(filepath, self._rules)

    if err then
        return false, err
    end

    -- Merge overrides with existing weights
    for key, weight in pairs(overrides) do
        self._weights[key] = weight
    end

    return true, nil
end

function ACE:TrainFromDemos(demos, opts)
    local training = require("dslua.agents.ace_training")
    local result = training.TrainFromDemos(demos, self._rules, opts)

    -- Update ACE weights with trained weights
    for key, weight in pairs(result.trained_weights) do
        self._weights[key] = weight
    end

    return result
end

function ACE:TrainFromDemoDirectory(directory, opts)
    opts = opts or {}
    local training = require("dslua.agents.ace_training")

    -- Load demos
    local demos, err = training.LoadDemos(directory, {
        validate = true,
        split_ratio = opts.split_ratio or 0.8,
        shuffle = opts.shuffle ~= false,
        seed = opts.seed
    })

    if err then
        return nil, err
    end

    -- Train
    return self:TrainFromDemos(demos, opts)
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

        -- If action produced an answer, we're done (REASON, RETRIEVE, DECOMPOSE, SYNTHESIZE, VERIFY all delegate to REASON)
        if action_result.answer then
            return self:_FormatResult(state, "SUCCESS")
        end
    end

    -- Timeout
    return self:_FormatResult(state, "TIMEOUT")
end

function ACE:_ExecuteAction(ctx, state, action)
    -- Wrap in pcall for error handling
    local ok, result = pcall(function()
        if action == "REASON" then
            local input = {question = state.original_input}
            return self._module:Process(ctx, input)
        elseif action == "DECOMPOSE" then
            return self:_ExecuteAction(ctx, state, "REASON")
        elseif action == "RETRIEVE" then
            return self:_ExecuteAction(ctx, state, "REASON")
        elseif action == "SYNTHESIZE" then
            return self:_ExecuteAction(ctx, state, "REASON")
        elseif action == "VERIFY" then
            return self:_ExecuteAction(ctx, state, "REASON")
        else
            return self:_ExecuteAction(ctx, state, "REASON")
        end
    end)

    if not ok then
        -- Error occurred, return empty result
        return {
            answer = nil,
            confidence = 0.1,
            error = result
        }
    end

    -- Parse response to extract answer
    if type(result) == "table" and result.content then
        return self:_ParseLLMResponse(result.content)
    else
        return result or {}
    end
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
