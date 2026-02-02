-- dslua/agents/ace_pattern_mining.lua
-- ACE Phase 3: Pattern Mining from Execution Outcomes

local M = {}

local EPS = 1e-9

-- =============================================================================
-- MinePatterns - Discover patterns from execution traces
-- =============================================================================

function M.MinePatterns(traces, opts)
  opts = opts or {}
  local min_success_rate = opts.min_success_rate or 0.8
  local min_uses = opts.min_uses or 3

  -- Group traces by action and features
  local pattern_groups = {}

  for _, trace in ipairs(traces) do
    -- Skip failed traces
    if not trace.outcome.success then
      goto continue
    end

    -- Create feature signature for grouping
    local signature = M._createFeatureSignature(trace.features)
    local action = trace.action

    local key = action .. ":" .. signature

    if not pattern_groups[key] then
      pattern_groups[key] = {
        action = action,
        features = trace.features,
        successes = 0,
        failures = 0,
        total = 0,
        trace_indices = {}
      }
    end

    local group = pattern_groups[key]
    group.total = group.total + 1
    group.successes = group.successes + 1
    table.insert(group.trace_indices, #pattern_groups[key].trace_indices + 1)

    ::continue::
  end

  -- Convert groups to patterns
  local patterns = {}
  local pattern_id = 0

  for key, group in pairs(pattern_groups) do
    if group.total >= min_uses then
      local success_rate = group.successes / group.total

      if success_rate >= min_success_rate then
        pattern_id = pattern_id + 1

        table.insert(patterns, {
          id = string.format("pattern_%03d", pattern_id),
          state_features = group.features,
          recommended_action = group.action,
          statistics = {
            success_count = group.successes,
            failure_count = group.total - group.successes,
            total_uses = group.total,
            success_rate = success_rate
          },
          source_traces = group.trace_indices
        })
      end
    end
  end

  return patterns
end

-- =============================================================================
-- PatternToRule - Convert pattern to ACE rule format
-- =============================================================================

function M.PatternToRule(pattern)
  -- Initial weight based on success rate (scale to [0.3, 1.0])
  local base_weight = 0.3 + (pattern.statistics.success_rate * 0.7)

  -- Apply coverage bonus (more uses = slightly higher weight)
  local coverage_bonus = math.log(pattern.statistics.total_uses) * 0.05
  local weight = math.min(1.0, base_weight + coverage_bonus)

  -- Build conditions from features
  local conditions = {}

  if pattern.state_features.task_type then
    conditions.task_type = pattern.state_features.task_type
  end

  if pattern.state_features.complexity_estimate then
    conditions.complexity_min = pattern.state_features.complexity_estimate - 0.1
    conditions.complexity_max = pattern.state_features.complexity_estimate + 0.1
  end

  if pattern.state_features.tool_requirements then
    conditions.tool_requirements = pattern.state_features.tool_requirements
  end

  return {
    id = "mined_" .. pattern.id,
    name = pattern.state_features.task_type .. "_" .. pattern.recommended_action:lower(),
    action = pattern.recommended_action,
    conditions = conditions,
    weight = weight,
    description = string.format("Mined from %d traces (%.0f%% success)",
      pattern.statistics.total_uses,
      pattern.statistics.success_rate * 100
    ),
    source = "pattern_mining",
    confidence = pattern.statistics.success_rate
  }
end

-- =============================================================================
-- ScorePattern - Score pattern quality based on success rate and coverage
-- =============================================================================

function M.ScorePattern(pattern, traces)
  -- Quality metrics
  local success_rate = pattern.statistics.success_rate or 0.5

  -- Coverage: how many traces match this pattern
  local coverage = 0
  if pattern.statistics.total_uses and #traces > 0 then
    coverage = pattern.statistics.total_uses / #traces
  end

  -- Specificity: more specific patterns (more conditions) should have higher success rate
  local condition_count = 0
  for k, v in pairs(pattern.state_features) do
    if k ~= "task_type" and v ~= nil then
      condition_count = condition_count + 1
    end
  end

  -- Combine metrics with weighted scoring
  -- Success rate: 60% weight
  -- Coverage: 20% weight (prefer patterns that apply to more traces)
  -- Specificity: 20% weight (prefer patterns with more discriminating features)
  local score = (success_rate * 0.6) +
                (math.min(1.0, coverage * 5) * 0.2) +  -- Scale coverage bonus
                (math.min(1.0, condition_count / 3) * 0.2)

  return math.min(1.0, score)
end

-- =============================================================================
-- Private helper functions
-- =============================================================================

function M._createFeatureSignature(features)
  -- Create a string signature for grouping similar traces
  local parts = {}

  if features.task_type then
    table.insert(parts, "type=" .. features.task_type)
  end

  if features.complexity_estimate then
    -- Bin complexity into ranges: low (<0.4), medium (0.4-0.7), high (>=0.7)
    local bin = "medium"
    if features.complexity_estimate < 0.4 then
      bin = "low"
    elseif features.complexity_estimate >= 0.7 then
      bin = "high"
    end
    table.insert(parts, "complexity=" .. bin)
  end

  if features.tool_requirements and #features.tool_requirements > 0 then
    table.insert(parts, "tools=" .. table.concat(features.tool_requirements, ","))
  end

  return table.concat(parts, "|")
end

return M
