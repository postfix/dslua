-- dslua/agents/ace_threshold.lua
-- ACE Threshold Learning - Adapt rule matching thresholds based on experience

local M = {}

-- =============================================================================
-- OptimizeThreshold - Find optimal threshold for a rule
-- =============================================================================

function M.OptimizeThreshold(rule_key, decision_history, opts)
  opts = opts or {}

  -- Extract outcomes and salience values
  local data = {}
  for _, record in ipairs(decision_history) do
    if record.rule_key == rule_key or string.find(record.rule_key, rule_key) then
      table.insert(data, {
        salience = record.salience,
        matched = record.matched,
        success = record.success,
        outcome_quality = record.outcome_quality or 0
      })
    end
  end

  if #data == 0 then
    return nil, "No decision history for rule: " .. tostring(rule_key)
  end

  -- Find optimal threshold using grid search
  local method = opts.method or "f1"
  local best_threshold = 0.5
  local best_score = -math.huge

  for threshold = 0.0, 1.0, 0.05 do
    local score = M._evaluateThreshold(data, threshold, method)

    if score > best_score then
      best_score = score
      best_threshold = threshold
    end
  end

  -- Fine-tune around best threshold
  for threshold = best_threshold - 0.05, best_threshold + 0.05, 0.01 do
    if threshold >= 0.0 and threshold <= 1.0 then
      local score = M._evaluateThreshold(data, threshold, method)

      if score > best_score then
        best_score = score
        best_threshold = threshold
      end
    end
  end

  return {
    threshold = best_threshold,
    score = best_score,
    method = method,
    sample_size = #data
  }
end

-- =============================================================================
-- OptimizeAllThresholds - Optimize thresholds for all rules
-- =============================================================================

function M.OptimizeAllThresholds(rules, decision_history, opts)
  opts = opts or {}

  local results = {}

  for _, rule in ipairs(rules) do
    local result, err = M.OptimizeThreshold(rule.key, decision_history, opts)

    if result then
      results[rule.key] = result
    else
      -- Keep default threshold if optimization failed
      results[rule.key] = {
        threshold = rule.threshold or 0.5,
        score = 0,
        method = opts.method or "f1",
        sample_size = 0,
        error = err
      }
    end
  end

  return results
end

-- =============================================================================
-- AdaptThreshold - Online threshold adaptation
-- =============================================================================

function M.AdaptThreshold(current_threshold, recent_outcomes, opts)
  opts = opts or {}

  local alpha = opts.alpha or 0.1  -- Adaptation rate
  local target_metric = opts.target_metric or "precision"
  local min_threshold = opts.min_threshold or 0.1
  local max_threshold = opts.max_threshold or 0.9

  -- Compute metric on recent outcomes
  local metric = M._computeMetric(recent_outcomes, target_metric)

  -- Compare to target
  local target = opts.target or 0.8

  -- Adjust threshold
  local adjustment = 0
  if metric < target then
    -- Below target: adjust threshold to improve metric
    if target_metric == "precision" then
      -- Low precision: increase threshold to be more selective
      adjustment = alpha * (target - metric)
    elseif target_metric == "recall" then
      -- Low recall: decrease threshold to be more permissive
      adjustment = -alpha * (target - metric)
    else
      -- For F1 or accuracy, direction depends on current threshold
      if current_threshold > 0.5 then
        adjustment = -alpha * (target - metric)  -- Lower threshold
      else
        adjustment = alpha * (target - metric)   -- Raise threshold
      end
    end
  end

  local new_threshold = current_threshold + adjustment

  -- Clamp to valid range
  new_threshold = math.max(min_threshold, math.min(max_threshold, new_threshold))

  return new_threshold, metric
end

-- =============================================================================
-- AnalyzeThresholdSensitivity - Analyze threshold impact on performance
-- =============================================================================

function M.AnalyzeThresholdSensitivity(rule_key, decision_history, opts)
  opts = opts or {}

  local thresholds = {}
  local min_threshold = opts.min_threshold or 0.0
  local max_threshold = opts.max_threshold or 1.0
  local step = opts.step or 0.1

  -- Extract data for this rule
  local data = {}
  for _, record in ipairs(decision_history) do
    if record.rule_key == rule_key or string.find(record.rule_key, rule_key) then
      table.insert(data, record)
    end
  end

  if #data == 0 then
    return nil, "No decision history for rule: " .. tostring(rule_key)
  end

  -- Evaluate at different thresholds
  for threshold = min_threshold, max_threshold, step do
    local metrics = M._computeMetricsAtThreshold(data, threshold)

    table.insert(thresholds, {
      threshold = threshold,
      metrics = metrics
    })
  end

  -- Find sensitivity metrics
  local sensitivity = {
    rule_key = rule_key,
    optimal_threshold = thresholds[1],
    sensitivity_score = 0,
    robust_range = {0.0, 1.0},
    analysis = thresholds
  }

  -- Find optimal threshold
  local best_f1 = -math.huge
  for _, t in ipairs(thresholds) do
    if t.metrics.f1 > best_f1 then
      best_f1 = t.metrics.f1
      sensitivity.optimal_threshold = t.threshold
    end
  end

  -- Find robust range (within 10% of optimal)
  local lower_bound = sensitivity.optimal_threshold
  local upper_bound = sensitivity.optimal_threshold

  for _, t in ipairs(thresholds) do
    if t.metrics.f1 >= best_f1 * 0.9 then
      if t.threshold < lower_bound then
        lower_bound = t.threshold
      end
      if t.threshold > upper_bound then
        upper_bound = t.threshold
      end
    end
  end

  sensitivity.robust_range = {lower_bound, upper_bound}
  sensitivity.sensitivity_score = upper_bound - lower_bound  -- Wider range = more robust

  return sensitivity
end

-- =============================================================================
-- RecommendThreshold - Recommend threshold based on rule characteristics
-- =============================================================================

function M.RecommendThreshold(rule, opts)
  opts = opts or {}

  local base_threshold = 0.5

  -- Adjust based on rule type
  local rule_type = rule.type or "default"

  if rule_type == "conservative" then
    -- Conservative: high threshold, only match when very confident
    base_threshold = 0.7
  elseif rule_type == "aggressive" then
    -- Aggressive: low threshold, match more freely
    base_threshold = 0.3
  elseif rule_type == "balanced" then
    base_threshold = 0.5
  end

  -- Adjust based on rule complexity
  if rule.complexity then
    if rule.complexity == "high" then
      -- Complex rules: higher threshold to avoid false positives
      base_threshold = base_threshold + 0.1
    elseif rule.complexity == "low" then
      -- Simple rules: lower threshold to encourage matching
      base_threshold = base_threshold - 0.1
    end
  end

  -- Adjust based on rule importance
  if rule.importance then
    if rule.importance == "critical" then
      -- Critical rules: higher threshold for precision
      base_threshold = base_threshold + 0.15
    elseif rule.importance == "optional" then
      -- Optional rules: lower threshold for recall
      base_threshold = base_threshold - 0.1
    end
  end

  -- Clamp to valid range
  base_threshold = math.max(0.0, math.min(1.0, base_threshold))

  return base_threshold
end

-- =============================================================================
-- ComputeThresholdStats - Compute statistics about threshold usage
-- =============================================================================

function M.ComputeThresholdStats(thresholds, decision_history, opts)
  opts = opts or {}

  local stats = {}

  for rule_key, threshold in pairs(thresholds) do
    local data = {}
    for _, record in ipairs(decision_history) do
      if record.rule_key == rule_key or string.find(record.rule_key, rule_key) then
        table.insert(data, record)
      end
    end

    if #data > 0 then
      local metrics = M._computeMetricsAtThreshold(data, threshold)

      stats[rule_key] = {
        threshold = threshold,
        metrics = metrics,
        sample_size = #data,
        utilization = M._computeUtilization(data, threshold)
      }
    else
      stats[rule_key] = {
        threshold = threshold,
        metrics = {precision = 0, recall = 0, f1 = 0, accuracy = 0},
        sample_size = 0,
        utilization = 0
      }
    end
  end

  return stats
end

-- =============================================================================
-- Private helper functions
-- =============================================================================

function M._evaluateThreshold(data, threshold, method)
  -- Filter decisions by threshold
  local matched = {}
  local total = 0
  local true_positives = 0
  local false_positives = 0
  local false_negatives = 0

  for _, record in ipairs(data) do
    if record.salience >= threshold then
      table.insert(matched, record)

      if record.success then
        true_positives = true_positives + 1
      else
        false_positives = false_positives + 1
      end
    else
      if record.success then
        false_negatives = false_negatives + 1
      end
    end

    total = total + 1
  end

  -- Compute metric
  local precision = true_positives + false_positives > 0 and
                    true_positives / (true_positives + false_positives) or 0
  local recall = true_positives + false_negatives > 0 and
                true_positives / (true_positives + false_negatives) or 0
  local f1 = precision + recall > 0 and (2 * precision * recall) / (precision + recall) or 0
  local accuracy = total > 0 and true_positives / total or 0

  if method == "precision" then
    return precision
  elseif method == "recall" then
    return recall
  elseif method == "f1" then
    return f1
  elseif method == "accuracy" then
    return accuracy
  else
    return f1
  end
end

function M._computeMetric(outcomes, metric_name)
  if #outcomes == 0 then
    return 0
  end

  local true_positives = 0
  local false_positives = 0
  local false_negatives = 0
  local total = #outcomes

  for _, outcome in ipairs(outcomes) do
    if outcome.matched then
      if outcome.success then
        true_positives = true_positives + 1
      else
        false_positives = false_positives + 1
      end
    else
      if outcome.success then
        false_negatives = false_negatives + 1
      end
    end
  end

  local precision = true_positives + false_positives > 0 and
                    true_positives / (true_positives + false_positives) or 0
  local recall = true_positives + false_negatives > 0 and
                true_positives / (true_positives + false_negatives) or 0
  local f1 = precision + recall > 0 and (2 * precision * recall) / (precision + recall) or 0
  local accuracy = total > 0 and true_positives / total or 0

  if metric_name == "precision" then
    return precision
  elseif metric_name == "recall" then
    return recall
  elseif metric_name == "f1" then
    return f1
  elseif metric_name == "accuracy" then
    return accuracy
  else
    return f1
  end
end

function M._computeMetricsAtThreshold(data, threshold)
  local true_positives = 0
  local false_positives = 0
  local false_negatives = 0
  local true_negatives = 0
  local total = #data

  for _, record in ipairs(data) do
    local matched = record.salience >= threshold

    if matched then
      if record.success then
        true_positives = true_positives + 1
      else
        false_positives = false_positives + 1
      end
    else
      if record.success then
        false_negatives = false_negatives + 1
      else
        true_negatives = true_negatives + 1
      end
    end
  end

  local precision = true_positives + false_positives > 0 and
                    true_positives / (true_positives + false_positives) or 0
  local recall = true_positives + false_negatives > 0 and
                true_positives / (true_positives + false_negatives) or 0
  local f1 = precision + recall > 0 and (2 * precision * recall) / (precision + recall) or 0
  local accuracy = total > 0 and (true_positives + true_negatives) / total or 0

  return {
    true_positives = true_positives,
    false_positives = false_positives,
    false_negatives = false_negatives,
    true_negatives = true_negatives,
    precision = precision,
    recall = recall,
    f1 = f1,
    accuracy = accuracy
  }
end

function M._computeUtilization(data, threshold)
  local matched = 0
  for _, record in ipairs(data) do
    if record.salience >= threshold then
      matched = matched + 1
    end
  end

  return #data > 0 and matched / #data or 0
end

return M
