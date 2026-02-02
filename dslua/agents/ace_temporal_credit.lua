-- dslua/agents/ace_temporal_credit.lua
-- ACE Temporal Credit Assignment - Distribute credit across multi-step executions

local M = {}

-- =============================================================================
-- ClassifyOutcome - Determine if execution was successful
-- =============================================================================

function M.ClassifyOutcome(trace, opts)
  opts = opts or {}

  -- Default success criteria
  local has_error = trace.error ~= nil
  local has_result = trace.final_result ~= nil
  local step_count = trace.steps and #trace.steps or 0

  -- Check custom success criteria if provided
  local custom_criteria = opts.success_criteria
  local custom_success = false
  if custom_criteria then
    custom_success = custom_criteria(trace)
  end

  -- Determine success
  local success = not has_error and has_result and (custom_criteria == nil or custom_success)

  -- Calculate confidence based on multiple factors
  local confidence = 1.0

  if has_error then
    confidence = 0.0
  elseif not has_result then
    confidence = 0.3
  else
    -- Higher confidence for:
    -- - More steps (complex task completed)
    -- - No errors in intermediate steps
    local steps_with_errors = 0
    if trace.steps then
      for _, step in ipairs(trace.steps) do
        if step.error then
          steps_with_errors = steps_with_errors + 1
        end
      end
    end

    local error_ratio = steps_with_errors / math.max(step_count, 1)
    confidence = confidence * (1.0 - error_ratio * 0.5)

    -- Adjust for step count (more steps = higher confidence if successful)
    if step_count > 3 then
      confidence = confidence * 1.2
    end
  end

  confidence = math.min(1.0, math.max(0.0, confidence))

  -- Generate reason
  local reason = success and "Task completed successfully" or "Task failed"

  if has_error then
    reason = reason .. ": " .. tostring(trace.error)
  elseif step_count == 0 then
    reason = reason .. ": No execution steps"
  end

  return {
    success = success,
    confidence = confidence,
    reason = reason
  }
end

-- =============================================================================
-- AnalyzeTrace - Extract features from execution trace
-- =============================================================================

function M.AnalyzeTrace(trace, opts)
  opts = opts or {}

  local analysis = {
    step_count = #trace.steps,
    total_duration_ms = 0,
    decision_points = {},
    tool_uses = {},
    error_steps = 0,
    successful_steps = 0
  }

  -- Analyze each step
  for i, step in ipairs(trace.steps) do
    -- Duration
    if step.duration_ms then
      analysis.total_duration_ms = analysis.total_duration_ms + step.duration_ms
    end

    -- Decision points
    if step.decision then
      table.insert(analysis.decision_points, {
        step_index = i,
        rule_id = step.decision.rule_id,
        salience = step.decision.salience or 0,
        outcome = step.decision.outcome
      })
    end

    -- Tool uses
    if step.tool then
      local tool_name = step.tool.name or "unknown"
      analysis.tool_uses[tool_name] = (analysis.tool_uses[tool_name] or 0) + 1
    end

    -- Errors
    if step.error then
      analysis.error_steps = analysis.error_steps + 1
    else
      analysis.successful_steps = analysis.successful_steps + 1
    end
  end

  -- Success ratio
  analysis.success_ratio = analysis.successful_steps / math.max(analysis.step_count, 1)

  -- Average duration per step
  analysis.avg_step_duration_ms = analysis.total_duration_ms / math.max(analysis.step_count, 1)

  return analysis
end

-- =============================================================================
-- AssignCredit - Distribute credit across steps using temporal difference learning
-- =============================================================================

function M.AssignCredit(trace, outcome, analysis, opts)
  opts = opts or {}

  local alpha = opts.alpha or 0.1  -- Learning rate
  local gamma = opts.gamma or 0.9  -- Discount factor
  local lambda = opts.lambda or 0.5  -- Eligibility trace decay

  -- Base reward from outcome
  local base_reward = outcome.success and 1.0 or -1.0
  local reward = base_reward * outcome.confidence

  -- Initialize credits for each decision
  local credits = {}

  -- Temporal difference learning
  local step_count = #trace.steps

  for i = step_count, 1, -1 do
    local step = trace.steps[i]

    if step.decision then
      local rule_id = step.decision.rule_id

      -- Calculate eligibility trace
      local eligibility = math.pow(lambda, step_count - i)

      -- Temporal difference: reward + discounted future value
      local future_value = 0

      if i < step_count then
        -- Look ahead to estimate future value
        for j = i + 1, step_count do
          local future_step = trace.steps[j]
          if future_step.decision and future_step.decision.value then
            future_value = future_value + math.pow(gamma, j - i) * future_step.decision.value
          end
        end
      end

      -- TD error
      local td_error = reward + gamma * future_value - (step.decision.value or 0)

      -- Credit assignment
      local credit = alpha * td_error * eligibility

      -- Accumulate credit for this rule
      if not credits[rule_id] then
        credits[rule_id] = {
          rule_id = rule_id,
          total_credit = 0,
          contributions = {}
        }
      end

      credits[rule_id].total_credit = credits[rule_id].total_credit + credit

      table.insert(credits[rule_id].contributions, {
        step_index = i,
        credit = credit,
        eligibility = eligibility,
        td_error = td_error
      })
    end
  end

  return credits
end

-- =============================================================================
-- DistributeCreditBySalience - Alternative: Distribute based on salience
-- =============================================================================

function M.DistributeCreditBySalience(trace, outcome, analysis, opts)
  opts = opts or {}

  local total_reward = outcome.success and outcome.confidence or -outcome.confidence

  -- Collect all decision points with salience
  local decisions = {}
  local total_salience = 0

  for i, step in ipairs(trace.steps) do
    if step.decision then
      local salience = step.decision.salience or 1.0
      total_salience = total_salience + salience

      table.insert(decisions, {
        step_index = i,
        rule_id = step.decision.rule_id,
        salience = salience
      })
    end
  end

  -- Distribute credit proportionally to salience
  local credits = {}

  for _, decision in ipairs(decisions) do
    local rule_id = decision.rule_id
    local proportion = decision.salience / total_salience
    local credit = total_reward * proportion

    if not credits[rule_id] then
      credits[rule_id] = {
        rule_id = rule_id,
        total_credit = 0,
        contributions = {}
      }
    end

    credits[rule_id].total_credit = credits[rule_id].total_credit + credit

    table.insert(credits[rule_id].contributions, {
      step_index = decision.step_index,
      credit = credit,
      salience = decision.salience,
      proportion = proportion
    })
  end

  return credits
end

-- =============================================================================
-- ComputeTemporalDifferences - Compute TD values for each step
-- =============================================================================

function M.ComputeTemporalDifferences(trace, outcome, opts)
  opts = opts or {}

  local gamma = opts.gamma or 0.9  -- Discount factor

  -- Base reward
  local reward = outcome.success and outcome.confidence or -outcome.confidence

  -- Compute TD values
  local tds = {}

  for i = #trace.steps, 1, -1 do
    local step = trace.steps[i]

    -- Current value
    local current_value = 0
    if step.decision then
      current_value = step.decision.value or 0
    end

    -- Next value (discounted)
    local next_value = 0
    if i < #trace.steps then
      local next_step = trace.steps[i + 1]
      if next_step.decision then
        next_value = next_step.decision.value or 0
      end
    end

    -- Temporal difference
    local td = reward + gamma * next_value - current_value

    table.insert(tds, 1, {
      step_index = i,
      td_error = td,
      current_value = current_value,
      next_value = next_value,
      reward = reward
    })
  end

  return tds
end

-- =============================================================================
-- AssignCreditByRecency - Weight recent steps more heavily
-- =============================================================================

function M.AssignCreditByRecency(trace, outcome, analysis, opts)
  opts = opts or {}

  local decay = opts.decay or 0.8  -- Recency decay factor

  local total_reward = outcome.success and outcome.confidence or -outcome.confidence

  -- Assign credit with recency bias
  local credits = {}
  local step_count = #trace.steps

  for i, step in ipairs(trace.steps) do
    if step.decision then
      local rule_id = step.decision.rule_id

      -- Recency weight: more recent steps get higher weight
      local recency_weight = math.pow(decay, step_count - i)

      local credit = total_reward * recency_weight

      if not credits[rule_id] then
        credits[rule_id] = {
          rule_id = rule_id,
          total_credit = 0,
          contributions = {}
        }
      end

      credits[rule_id].total_credit = credits[rule_id].total_credit + credit

      table.insert(credits[rule_id].contributions, {
        step_index = i,
        credit = credit,
        recency_weight = recency_weight
      })
    end
  end

  return credits
end

-- =============================================================================
-- AggregateCredits - Aggregate credits from multiple traces
-- =============================================================================

function M.AggregateCredits(credits_list, opts)
  opts = opts or {}

  local aggregated = {}

  for _, credits in ipairs(credits_list) do
    for rule_id, credit_info in pairs(credits) do
      -- Skip if credit_info is not properly structured
      if type(credit_info) == "table" and credit_info.total_credit ~= nil then
        if not aggregated[rule_id] then
          aggregated[rule_id] = {
            rule_id = rule_id,
            total_credit = 0,
            contribution_count = 0,
            contributions = {}
          }
        end

        aggregated[rule_id].total_credit = aggregated[rule_id].total_credit + credit_info.total_credit

        -- Add contribution count if present, otherwise count as 1
        local count = credit_info.contribution_count or 1
        aggregated[rule_id].contribution_count = aggregated[rule_id].contribution_count + count

        -- Merge contributions if tracking details
        if opts.keep_details and credit_info.contributions then
          for _, contrib in ipairs(credit_info.contributions) do
            table.insert(aggregated[rule_id].contributions, contrib)
          end
        end
      end
    end
  end

  return aggregated
end

-- =============================================================================
-- NormalizeCredits - Normalize credits to [0, 1] range
-- =============================================================================

function M.NormalizeCredits(credits, opts)
  opts = opts or {}

  -- Find min and max credits
  local min_credit = math.huge
  local max_credit = -math.huge

  for rule_id, credit_info in pairs(credits) do
    if credit_info.total_credit < min_credit then
      min_credit = credit_info.total_credit
    end
    if credit_info.total_credit > max_credit then
      max_credit = credit_info.total_credit
    end
  end

  -- Normalize
  local normalized = {}
  local range = max_credit - min_credit

  for rule_id, credit_info in pairs(credits) do
    local norm_credit = 0

    if range > 0 then
      norm_credit = (credit_info.total_credit - min_credit) / range
    else
      norm_credit = 0.5  -- All same credit
    end

    normalized[rule_id] = {
      rule_id = rule_id,
      total_credit = credit_info.total_credit,
      normalized_credit = norm_credit,
      contribution_count = credit_info.contribution_count
    }
  end

  return normalized
end

return M
