-- dslua/agents/ace_decision.lua
local M = {}

local DEFAULTS = {
  task = {
    complexity_estimate = 0.5,
    input_length = 0.0,
    entity_count = 0.0,
    tool_requirements = {}
  },
  self = {
    confidence = 0.5,
    steps_taken = 0,
    prev_action = nil
  }
}

function M.NormalizeState(snapshot)
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
      self = self,
      history = snapshot.history or {}
    }
  end

  -- Not normalized, return as-is (shouldn't happen in production)
  return snapshot
end

function M.ComputeSalience(rule, state, opts)
  local mode = opts.salience_mode or "binary"

  if mode == "binary" then
    local matches = M._RuleMatches(rule, state)
    local raw = matches and 1.0 or 0.0
    return raw, {mode = mode, coerced = false, raw = raw}
  else
    error("Invalid salience_mode")
  end
end

function M._RuleMatches(rule, state)
  for _, condition in ipairs(rule.conditions) do
    if not M._ConditionMatches(condition, state) then
      return false
    end
  end
  return true
end

function M._ConditionMatches(condition, state)
  local feature_value = M._GetFeatureValue(state, condition.feature)
  if feature_value == nil then
    return false
  end

  local op = condition.op

  if op == "==" then
    return feature_value == condition.value
  elseif op == ">" then
    return feature_value > condition.threshold
  elseif op == "<" then
    return feature_value < condition.threshold
  elseif op == ">=" then
    return feature_value >= condition.threshold
  elseif op == "<=" then
    return feature_value <= condition.threshold
  else
    return false
  end
end

function M._GetFeatureValue(state, feature_name)
  -- Search in task layer
  if state.task and state.task[feature_name] ~= nil then
    return state.task[feature_name]
  end

  -- Search in self layer
  if state.self and state.self[feature_name] ~= nil then
    return state.self[feature_name]
  end

  -- Search in history layer
  if state.history and state.history[feature_name] ~= nil then
    return state.history[feature_name]
  end

  return nil
end

function M.FindMatchingRules(state, action, rules, weights, ACTIONS_ORDER)
  local matches = {}

  for _, rule in ipairs(rules) do
    -- Check if rule applies to this action
    if rule.action == action then
      -- Check if rule conditions match state
      if M._RuleMatches(rule, state) then
        local weight = weights[rule.key] or rule.default_weight
        local salience, _ = M.ComputeSalience(rule, state, {salience_mode = "binary"})

        table.insert(matches, {
          rule = rule,
          key = rule.key,
          weight = weight,
          salience = salience
        })
      end
    end
  end

  return matches
end

function M.ScoreActions(state, rules, weights, ACTIONS_ORDER)
  local scores = {}
  local per_action_matches = {}

  for _, action in ipairs(ACTIONS_ORDER) do
    local matches = M.FindMatchingRules(state, action, rules, weights, ACTIONS_ORDER)
    per_action_matches[action] = matches

    local score = 0
    for _, pair in ipairs(matches) do
      score = score + (pair.weight * pair.salience)
    end
    scores[action] = score
  end

  return scores, per_action_matches
end

function M.PredictAction(scores, ACTIONS_ORDER)
  local best_action = ACTIONS_ORDER[1]
  local best_score = nil

  for _, action in ipairs(ACTIONS_ORDER) do
    local s = scores[action] or 0
    if best_score == nil or s > best_score then
      best_score = s
      best_action = action
    end
  end

  return best_action
end

return M
