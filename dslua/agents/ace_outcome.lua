-- dslua/agents/ace_outcome.lua
-- ACE Phase 3: Outcome Tracking & Classification

local M = {}

-- =============================================================================
-- ClassifyOutcome - Classify execution outcome as success/failure
-- =============================================================================

function M.ClassifyOutcome(trace, opts)
  opts = opts or {}

  -- Use custom success function if provided (overrides default logic)
  if opts.custom_success_fn then
    local success, custom_confidence, custom_reason = opts.custom_success_fn(trace)
    return {
      success = success,
      confidence = custom_confidence or 0.5,
      reason = custom_reason or "custom_criteria"
    }
  end

  -- Check for execution error (highest priority failure)
  if trace.error then
    return {
      success = false,
      confidence = 0.0,
      reason = "execution_error"
    }
  end

  -- Check if final result exists
  if not trace.final_result then
    return {
      success = false,
      confidence = 0.0,
      reason = "no_result"
    }
  end

  -- Extract confidence from result
  local confidence = trace.final_result.confidence or 0.5

  -- Check confidence threshold
  local min_confidence = opts.min_confidence or 0.7
  if confidence < min_confidence then
    return {
      success = false,
      confidence = confidence,
      reason = "low_confidence"
    }
  end

  -- Check max steps
  local max_steps = opts.max_steps or 10
  if trace.steps_taken and trace.steps_taken > max_steps then
    return {
      success = false,
      confidence = 0.0,
      reason = "max_steps_exceeded"
    }
  end

  -- Default: success if all checks pass
  return {
    success = true,
    confidence = confidence,
    reason = "valid_result"
  }
end

-- =============================================================================
-- ExtractFeatures - Extract features from execution trace for pattern mining
-- =============================================================================

function M.ExtractFeatures(trace)
  local features = {}

  -- Extract task features
  if trace.state_snapshot and trace.state_snapshot.task then
    local task = trace.state_snapshot.task
    features.task_type = task.task_type
    features.complexity_estimate = task.complexity_estimate
    features.input_length = task.input_length
    features.entity_count = task.entity_count
    features.tool_requirements = task.tool_requirements or {}
  end

  -- Extract action sequence
  features.actions = trace.actions or {}

  -- Extract tool usage
  features.tool_usage = trace.tool_usage or {}

  -- Extract confidence trajectory
  features.confidence_trajectory = trace.confidence_trajectory or {}

  -- Extract execution metrics
  features.steps_taken = trace.steps_taken or 0
  features.duration_ms = trace.duration_ms or 0

  return features
end

return M
