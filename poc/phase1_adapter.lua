local Phase1Adapter = {}
Phase1Adapter.__index = Phase1Adapter

function Phase1Adapter.new()
    return setmetatable({}, Phase1Adapter)
end

-- Default values for optional fields
local DEFAULTS = {
    task = {
        input_length = 0.0,
        entity_count = 0.0,
        tool_requirements = {}
    },
    self = {
        prev_action = nil
    }
}

function Phase1Adapter:NormalizeState(snapshot)
    -- Check if already normalized (has task and self layers)
    if snapshot.task and snapshot.self then
        -- Apply defaults for any missing optional fields
        local task = {}
        for k, v in pairs(snapshot.task) do
            task[k] = v
        end
        for k, v in pairs(DEFAULTS.task) do
            if task[k] == nil then
                task[k] = v
            end
        end

        local self = {}
        for k, v in pairs(snapshot.self) do
            self[k] = v
        end
        for k, v in pairs(DEFAULTS.self) do
            if self[k] == nil then
                self[k] = v
            end
        end

        return {
            task = task,
            self = self
        }
    end

    -- Raw snapshot passed through unchanged (assume already structured)
    return snapshot
end

function Phase1Adapter:ComputeSalience(rule, state, opts)
    local mode = opts.salience_mode or "binary"
    local diag = {mode = mode, coerced = false, raw = nil}

    if mode == "binary" then
        local raw = self:_RuleMatches(rule, state) and 1.0 or 0.0
        diag.raw = raw
        return raw, diag
    end

    if mode == "threshold" then
        local raw = self:_ContinuousSalience(rule, state)
        diag.raw = raw
        local threshold = opts.salience_threshold or 0.5
        local s = (raw >= threshold) and 1.0 or 0.0
        diag.coerced = (raw ~= s)
        return s, diag
    end

    error("Invalid salience_mode")
end

function Phase1Adapter:_RuleMatches(rule, state)
    for _, condition in ipairs(rule.conditions) do
        local feature_name = condition[1]
        local op = condition[2]
        local expected = condition[3]

        if not self:_ConditionMatches(state, feature_name, op, expected) then
            return false
        end
    end
    return true
end

function Phase1Adapter:_ConditionMatches(state, feature_name, op, expected)
    -- Find feature value in state (search task and self layers)
    local feature_value = nil

    if state.task and state.task[feature_name] ~= nil then
        feature_value = state.task[feature_name]
    elseif state.self and state.self[feature_name] ~= nil then
        feature_value = state.self[feature_name]
    end

    if feature_value == nil then
        return false
    end

    if op == "==" then
        return feature_value == expected
    elseif op == ">" then
        return feature_value > expected
    elseif op == "<" then
        return feature_value < expected
    elseif op == ">=" then
        return feature_value >= expected
    elseif op == "<=" then
        return feature_value <= expected
    else
        return false
    end
end

function Phase1Adapter:_ContinuousSalience(rule, state)
    -- Placeholder for Phase 3 continuous salience
    -- For Phase 2 POC, just return binary result
    return self:_RuleMatches(rule, state) and 1.0 or 0.0
end

function Phase1Adapter:FindMatchingRules(state, action, rules, weights)
    local matches = {}

    for _, rule in ipairs(rules) do
        -- Only check rules that target this action
        if rule.action == action then
            local salience, diag = self:ComputeSalience(rule, state, {salience_mode = "binary"})

            if salience > 0 then
                local key = rule.key or rule.id
                local w = weights[key]

                if w == nil then
                    if rule.default_weight ~= nil then
                        w = rule.default_weight
                    else
                        error("Missing weight for rule")
                    end
                end

                table.insert(matches, {
                    rule = rule,
                    salience = salience,
                    weight = w,
                    salience_diag = diag,
                    key = key
                })
            end
        end
    end

    return matches
end

function Phase1Adapter:ScoreActions(state, rules, weights, ACTIONS_ORDER)
    local scores = {}
    local per_action_matches = {}

    for _, action in ipairs(ACTIONS_ORDER) do
        local matches = self:FindMatchingRules(state, action, rules, weights)
        per_action_matches[action] = matches

        local score = 0
        for _, pair in ipairs(matches) do
            score = score + (pair.weight * pair.salience)
        end
        scores[action] = score
    end

    return scores, per_action_matches
end

return Phase1Adapter
