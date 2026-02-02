-- dslua/agents/ace_online_learning.lua
-- ACE Phase 3: Online Learning from Execution Outcomes

local M = {}

local MIN_WEIGHT = 0.1
local MAX_WEIGHT = 1.0
local EPS = 1e-9

-- =============================================================================
-- UpdateFromOutcome - Update weights based on execution outcome
-- =============================================================================

function M.UpdateFromOutcome(agent, trace, outcome, opts)
  opts = opts or {}
  local learning_rate = opts.learning_rate or 0.05
  local max_weight_delta = opts.max_weight_delta or 0.02

  local updated = false
  local total_delta = 0

  for _, step in ipairs(trace.steps) do
    if step.matching_rules and #step.matching_rules > 0 then
      -- Calculate credit for this step
      -- For now, use equal credit distribution (can be enhanced with temporal credit)
      local step_credit = 1.0 / #trace.steps

      -- Determine update direction and magnitude
      local direction = outcome.success and 1 or -1

      -- Use outcome confidence to scale magnitude, but ensure minimum update
      local outcome_confidence = outcome.confidence or (outcome.success and 1.0 or 0.5)
      if not outcome.success and outcome_confidence == 0 then
        outcome_confidence = 0.5  -- Ensure failures still cause updates
      end

      -- Calculate total contribution mass for this step
      local total_contribution = 0
      for _, pair in ipairs(step.matching_rules) do
        local contribution = pair.salience
        total_contribution = total_contribution + contribution
      end

      if total_contribution > EPS then
        -- Distribute updates by contribution
        for _, pair in ipairs(step.matching_rules) do
          local rule_id = pair.rule.id
          local current_weight = agent._weights[rule_id] or 0.5
          local contribution = pair.salience

          -- Calculate delta for this rule (distribute by salience)
          local delta_raw = learning_rate * step_credit * outcome_confidence * direction
          local delta = delta_raw * (contribution / total_contribution)

          -- Cap delta by max_weight_delta
          delta = math.max(-max_weight_delta, math.min(max_weight_delta, delta))

          -- Apply update with clamping
          local new_weight = math.max(MIN_WEIGHT, math.min(MAX_WEIGHT, current_weight + delta))
          agent._weights[rule_id] = new_weight

          updated = true
          total_delta = total_delta + math.abs(delta)
        end
      end
    end
  end

  return {
    updated = updated,
    total_delta = total_delta,
    steps_updated = #trace.steps,
    outcome_success = outcome.success
  }
end

-- =============================================================================
-- Experience Buffer - Store execution experiences for replay
-- =============================================================================

function M.NewExperienceBuffer(capacity)
  local buffer = {
    _capacity = capacity or 100,
    _experiences = {}
  }

  -- Push new experience
  function buffer:push(experience)
    -- Add to end (FIFO ordering)
    table.insert(self._experiences, experience)

    -- Enforce capacity (remove oldest if exceeded)
    if #self._experiences > self._capacity then
      table.remove(self._experiences, 1)  -- Remove oldest (first item)
    end
  end

  -- Get all experiences
  function buffer:GetAll()
    -- Return copy to prevent external modification
    local copy = {}
    for i, exp in ipairs(self._experiences) do
      copy[i] = exp
    end
    return copy
  end

  -- Get current size
  function buffer:Size()
    return #self._experiences
  end

  -- Sample random experiences for replay
  function buffer:Sample(count)
    local size = self:Size()
    count = math.min(count or 10, size)

    if size == 0 then
      return {}
    end

    local samples = {}
    local indices = {}

    -- Generate random indices
    while #indices < count do
      local idx = math.random(1, size)
      local already_selected = false

      for _, existing in ipairs(indices) do
        if existing == idx then
          already_selected = true
          break
        end
      end

      if not already_selected then
        table.insert(indices, idx)
      end
    end

    -- Collect samples
    for _, idx in ipairs(indices) do
      table.insert(samples, self._experiences[idx])
    end

    return samples
  end

  -- Clear buffer
  function buffer:Clear()
    self._experiences = {}
  end

  return buffer
end

return M
