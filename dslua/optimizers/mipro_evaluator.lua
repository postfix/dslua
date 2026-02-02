-- dslua/optimizers/mipro_evaluator.lua
-- MIPRO Evaluator - Evaluate candidate programs on validation sets

local M = {}

-- =============================================================================
-- EvaluateProgram - Test program on validation set
-- =============================================================================

function M.EvaluateProgram(program, valset, ctx, opts)
  opts = opts or {}

  local results = {}
  local total_correct = 0
  total_latency = 0

  for _, example in ipairs(valset) do
    local start_time = os.clock()

    -- Process the example with error handling
    local success, output = pcall(function()
      return program:Process(ctx, example.input)
    end)

    local end_time = os.clock()
    local latency_ms = (end_time - start_time) * 1000

    -- Check accuracy
    local correct = false
    if success and output then
      correct = M._checkAccuracy(output, example.output)
    end

    if correct then
      total_correct = total_correct + 1
    end

    table.insert(results, {
      output = output,
      expected = example.output,
      correct = correct,
      latency_ms = latency_ms
    })

    total_latency = total_latency + latency_ms
  end

  -- Compute metrics
  local metrics = {
    total_examples = #valset,
    correct_count = total_correct,
    accuracy = total_correct / #valset,
    results = results,
    avg_latency_ms = total_latency / #valset,
    total_latency_ms = total_latency
  }

  -- Apply custom metric function if provided
  if opts.metric_fn then
    metrics.custom_score = opts.metric_fn(results)
  end

  return metrics
end

-- =============================================================================
-- ComputeScore - Multi-objective weighted scoring
-- =============================================================================

function M.ComputeScore(metrics, weights)
  weights = weights or {}

  local score = 0
  local total_weight = 0

  -- Compute weighted sum
  for key, weight in pairs(weights) do
    if metrics[key] ~= nil then
      score = score + (metrics[key] * weight)
      total_weight = total_weight + math.abs(weight)
    end
  end

  -- Normalize by total weight
  if total_weight > 0 then
    score = score / total_weight
  else
    score = 0
  end

  return score
end

-- =============================================================================
-- Private helper functions
-- =============================================================================

function M._checkAccuracy(output, expected)
  -- Check if output matches expected
  -- Handle Predict module output format: {answer: "...", ...}

  if type(output) == "table" and type(expected) == "table" then
    -- Compare field by field
    for key, expected_val in pairs(expected) do
      local output_val = output[key]
      if output_val ~= expected_val then
        return false
      end
    end
    return true
  elseif type(output) == type(expected) then
    return output == expected
  else
    return false
  end
end

return M
