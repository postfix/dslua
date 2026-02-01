-- dslua/agents/ace_learning.lua
local Decision = require("dslua.agents.ace_decision")
local M = {}

local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}
local EPS = 1e-9

function M.LearnFromDemonstration(decision, rules, weights, opts, NormalizeState, ACTIONS_ORDER)
  local a_star = decision.demonstrated_action
  local state = NormalizeState(decision.state_snapshot)

  -- Validate demonstrated_action
  local valid_action = false
  for _, action in ipairs(ACTIONS_ORDER) do
    if action == a_star then
      valid_action = true
      break
    end
  end
  if not valid_action then
    error("Invalid demonstrated_action")
  end

  -- Step 1: Compute scores deterministically
  local scores, per_action_matches = Decision.ScoreActions(
    state, rules, weights, ACTIONS_ORDER
  )
  local score_star = scores[a_star]

  -- Step 2: Find best competitor
  local best = nil
  for _, action in ipairs(ACTIONS_ORDER) do
    if action ~= a_star then
      local s = scores[action] or 0
      if best == nil or s > best then
        best = s
      end
    end
  end
  local score_comp = best or 0

  -- Step 3: Build epsilon-band competitors
  local comp_actions = {}
  if score_comp > 0 then
    for _, action in ipairs(ACTIONS_ORDER) do
      if action ~= a_star then
        local s = scores[action] or 0
        if s >= score_comp - (opts.epsilon or 0.01) then
          table.insert(comp_actions, action)
        end
      end
    end
  end

  if #comp_actions == 0 then
    score_comp = 0
  end

  -- Step 4: Find matching rules for demonstrated action
  local R_star = Decision.FindMatchingRules(state, a_star, rules, weights, ACTIONS_ORDER)

  -- Step 5: Handle coverage failure
  if #R_star == 0 then
    return {
      updated = false,
      uncovered = true,
      reason = "no_rules_for_demonstrated_action",
      demonstrated_action = a_star
    }
  end

  -- Step 6: Compute contribution mass
  local mass_star = 0
  for _, pair in ipairs(R_star) do
    mass_star = mass_star + (pair.weight * pair.salience)
  end
  if mass_star <= EPS then
    return {
      updated = false,
      uncovered = false,
      reason = "zero_mass_star",
      mass_star = mass_star
    }
  end

  -- Step 7: Build flattened R_comp
  local R_comp = {}
  for _, action in ipairs(comp_actions) do
    local matches = Decision.FindMatchingRules(state, action, rules, weights, ACTIONS_ORDER)
    for _, pair in ipairs(matches) do
      table.insert(R_comp, pair)
    end
  end

  -- Step 8: Compute margin
  local margin = score_star - score_comp

  -- Step 9: Skip if sufficient margin
  if margin >= (opts.min_margin or 0.05) then
    return {
      updated = false,
      margin = margin,
      score_star = score_star,
      score_comp = score_comp,
      reason = "sufficient_margin"
    }
  end

  -- Step 10: Compute update budget
  local gap = (opts.min_margin or 0.05) - margin
  local delta_total = math.min(
    opts.max_weight_delta or 0.02,
    (opts.learning_rate or 0.05) * gap
  )

  -- Initialize metrics
  local metrics = {
    updated = true,
    margin = margin,
    gap = gap,
    delta_total = delta_total,
    score_star = score_star,
    score_comp = score_comp,
    clamp_events = {inc = {count = 0, rules = {}}, dec = {count = 0, rules = {}}},
    salience_coercions = {count = 0, rules = {}},
    comp_band_size = #comp_actions,
    mass_star = mass_star,
    demonstrated_action = a_star
  }

  -- Step 11: Increase weights for demonstrated action
  for _, pair in ipairs(R_star) do
    local key = pair.key
    local contribution = pair.weight * pair.salience
    local delta = delta_total * (contribution / mass_star)

    local old_w = weights[key]
    local new_w = math.min(1.0, math.max(0.1, old_w + delta))

    if new_w == 1.0 and delta > 0 then
      metrics.clamp_events.inc.count = metrics.clamp_events.inc.count + 1
      metrics.clamp_events.inc.rules[key] = (metrics.clamp_events.inc.rules[key] or 0) + 1
    end

    weights[key] = new_w
  end

  -- Step 12: Decrease weights for competitors
  if #R_comp > 0 then
    local mass_comp = 0
    for _, pair in ipairs(R_comp) do
      mass_comp = mass_comp + (pair.weight * pair.salience)
    end

    if mass_comp > EPS then
      for _, pair in ipairs(R_comp) do
        local key = pair.key
        local contribution = pair.weight * pair.salience
        local delta = delta_total * (contribution / mass_comp)

        local old_w = weights[key]
        local new_w = math.min(1.0, math.max(0.1, old_w - delta))

        if new_w == 0.1 and delta > 0 then
          metrics.clamp_events.dec.count = metrics.clamp_events.dec.count + 1
          metrics.clamp_events.dec.rules[key] = (metrics.clamp_events.dec.rules[key] or 0) + 1
        end

        weights[key] = new_w
      end
    end
  end

  return metrics
end

return M
