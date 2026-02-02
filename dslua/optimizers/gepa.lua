-- dslua/optimizers/gepa.lua
-- GEPA: Greedy Ensemble Prompt Augmentation Optimizer

local BaseOptimizer = require("dslua.optimizers.base")
local FewShot = require("dslua.modules.fewshot")

local M = {}
M.__index = M
setmetatable(M, {__index = BaseOptimizer})

-- =============================================================================
-- GEPA.new - Create GEPA optimizer
-- =============================================================================

function M.new(module, opts)
  opts = opts or {}

  -- Pass valset as dataset to parent for evaluation
  local parent_opts = {
    dataset = opts.valset or opts.dataset or {}
  }
  local self = BaseOptimizer.new(module, parent_opts)
  setmetatable(self, M)

  -- GEPA-specific options
  self._trainset = opts.trainset or {}
  self._valset = opts.valset or opts.dataset or {}
  self._ensemble_size = opts.ensemble_size or 3
  self._max_demonstrations_per_model = opts.max_demonstrations_per_model or 5
  self._aggregation_strategy = opts.aggregation_strategy or "majority_vote"  -- "majority_vote", "weighted", "confidence"
  self._max_trials = opts.max_trials or 20

  -- Tracking
  self._ensemble = {}
  self._weights = {}
  self._best_score = 0

  return self
end

-- =============================================================================
-- Compile - Optimize program using GEPA
-- =============================================================================

function M:Compile(ctx, num_trials)
  num_trials = num_trials or self._max_trials

  if #self._trainset == 0 then
    -- Return base module with no demonstrations
    local empty_program = FewShot.new(self._module, {})
    return empty_program, {
      score = 0,
      ensemble_size = 0,
      weights = {}
    }
  end

  print("[GEPA] Starting compilation...")
  print(string.format("  Trainset size: %d", #self._trainset))
  print(string.format("  Valset size: %d", #self._valset))
  print(string.format("  Ensemble size: %d", self._ensemble_size))
  print(string.format("  Aggregation: %s", self._aggregation_strategy))

  local best_ensemble = {}
  local best_weights = {}
  local best_score = -1

  -- Try different ensemble configurations
  for trial = 1, num_trials do
    -- Generate ensemble candidates
    local ensemble = self:_generateEnsemble()
    local weights = self:_calculateWeights(ensemble)

    -- Evaluate ensemble
    local score = 0
    if #self._valset > 0 then
      score = self:_evaluateEnsemble(ctx, ensemble, weights)
    else
      -- Use heuristic score if no valset
      score = self:_heuristicScore(ensemble)
    end

    if score > best_score then
      best_score = score
      best_ensemble = ensemble
      best_weights = weights
      print(string.format("  Trial %d: New best score %.4f", trial, score))
    end
  end

  -- Store tracking info
  self._ensemble = best_ensemble
  self._weights = best_weights
  self._best_score = best_score

  -- Create wrapper program for ensemble
  local ensemble_program = self:_createEnsembleProgram(best_ensemble, best_weights)

  print(string.format("  Final score: %.4f", best_score))
  print(string.format("  Ensemble size: %d", #best_ensemble))
  print("[GEPA] Compilation complete")

  return ensemble_program, {
    score = best_score,
    ensemble_size = #best_ensemble,
    weights = best_weights,
    models = best_ensemble
  }
end

-- =============================================================================
-- Private Helper Methods
-- =============================================================================

function M:_generateEnsemble()
  -- Generate ensemble of few-shot models
  local ensemble = {}

  for i = 1, self._ensemble_size do
    -- Select diverse subset for each model
    local subset = self:_selectDiverseSubset(i)
    local model = FewShot.new(self._module, subset)

    table.insert(ensemble, {
      model = model,
      demonstrations = subset,
      index = i
    })
  end

  return ensemble
end

function M:_selectDiverseSubset(seed)
  -- Select diverse demonstration subset based on seed
  local subset_size = math.min(self._max_demonstrations_per_model, #self._trainset)

  -- Shuffle with seed
  local shuffled = {}
  for i = 1, #self._trainset do
    shuffled[i] = self._trainset[i]
  end

  -- Fisher-Yates shuffle with seed
  math.randomseed(seed * os.time())
  for i = #shuffled, 2, -1 do
    local j = math.random(i)
    shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
  end

  -- Take first subset_size elements
  local subset = {}
  for i = 1, subset_size do
    subset[i] = shuffled[i]
  end

  return subset
end

function M:_calculateWeights(ensemble)
  -- Calculate weights for ensemble members
  local weights = {}

  if self._aggregation_strategy == "weighted" then
    -- Equal weights by default, could be refined
    for i = 1, #ensemble do
      weights[i] = 1.0 / #ensemble
    end
  elseif self._aggregation_strategy == "confidence" then
    -- Higher weight for models with more demonstrations
    local total_demos = 0
    for _, member in ipairs(ensemble) do
      total_demos = total_demos + #member.demonstrations
    end

    for i, member in ipairs(ensemble) do
      weights[i] = #member.demonstrations / total_demos
    end
  else  -- majority_vote
    -- Equal weights for majority voting
    for i = 1, #ensemble do
      weights[i] = 1.0
    end
  end

  return weights
end

function M:_evaluateEnsemble(ctx, ensemble, weights)
  -- Evaluate ensemble on validation set
  local total_score = 0

  for _, example in ipairs(self._valset) do
    local predictions = {}

    -- Collect predictions from all ensemble members
    for _, member in ipairs(ensemble) do
      local pred = member.model:Process(ctx, example.input or example)
      table.insert(predictions, pred)
    end

    -- Aggregate predictions
    local aggregated = self:_aggregatePredictions(predictions, weights)

    -- Score against expected output
    local score = self._metric(aggregated, example.output or example)
    total_score = total_score + score
  end

  return total_score / #self._valset
end

function M:_aggregatePredictions(predictions, weights)
  -- Aggregate predictions from ensemble
  if #predictions == 0 then
    return {}
  end

  if self._aggregation_strategy == "majority_vote" then
    return self:_majorityVote(predictions)
  elseif self._aggregation_strategy == "weighted" then
    return self:_weightedAggregation(predictions, weights)
  else  -- confidence
    return self:_confidenceWeightedAggregation(predictions, weights)
  end
end

function M:_majorityVote(predictions)
  -- Majority vote aggregation
  local result = {}
  local votes = {}

  -- Count votes for each answer
  for _, pred in ipairs(predictions) do
    local answer = pred.answer
    if answer then
      votes[answer] = (votes[answer] or 0) + 1
    end
  end

  -- Find most common answer
  local max_votes = 0
  local winner = nil

  for answer, count in pairs(votes) do
    if count > max_votes then
      max_votes = count
      winner = answer
    end
  end

  -- Build result from first prediction with winning answer
  for _, pred in ipairs(predictions) do
    if pred.answer == winner then
      for k, v in pairs(pred) do
        result[k] = v
      end
      break
    end
  end

  return result
end

function M:_weightedAggregation(predictions, weights)
  -- Weighted aggregation
  local result = {}
  local weighted_answers = {}

  -- Collect weighted answers
  for i, pred in ipairs(predictions) do
    local weight = weights[i] or (1.0 / #predictions)
    local answer = pred.answer

    if answer then
      if not weighted_answers[answer] then
        weighted_answers[answer] = 0
      end
      weighted_answers[answer] = weighted_answers[answer] + weight
    end
  end

  -- Find highest weighted answer
  local max_weight = 0
  local winner = nil

  for answer, weight in pairs(weighted_answers) do
    if weight > max_weight then
      max_weight = weight
      winner = answer
    end
  end

  -- Build result from first prediction with winning answer
  for _, pred in ipairs(predictions) do
    if pred.answer == winner then
      for k, v in pairs(pred) do
        result[k] = v
      end
      break
    end
  end

  return result
end

function M:_confidenceWeightedAggregation(predictions, weights)
  -- Confidence-weighted aggregation (similar to weighted but with confidence)
  -- For now, use same as weighted
  return self:_weightedAggregation(predictions, weights)
end

function M:_heuristicScore(ensemble)
  -- Heuristic score when no validation set
  -- Score based on diversity of demonstrations
  local total_unique = 0
  local seen = {}

  for _, member in ipairs(ensemble) do
    for _, demo in ipairs(member.demonstrations) do
      -- Create signature from demo
      local sig = self:_demoSignature(demo)
      if not seen[sig] then
        seen[sig] = true
        total_unique = total_unique + 1
      end
    end
  end

  -- Normalize by ensemble size
  return total_unique / (#ensemble * self._max_demonstrations_per_model)
end

function M:_demoSignature(demo)
  -- Create signature for demonstration
  local parts = {}

  for k, v in pairs(demo) do
    if k ~= "ctx" and type(v) == "string" then
      table.insert(parts, k .. ":" .. v)
    end
  end

  return table.concat(parts, "|")
end

function M:_createEnsembleProgram(ensemble, weights)
  -- Create wrapper program for ensemble
  local ensemble_program = {
    _ensemble = ensemble,
    _weights = weights,
    _aggregation_strategy = self._aggregation_strategy,
    _base_module = self._module
  }

  function ensemble_program:Process(ctx, input)
    local predictions = {}

    -- Collect predictions from all ensemble members
    for _, member in ipairs(self._ensemble) do
      local pred = member.model:Process(ctx, input)
      table.insert(predictions, pred)
    end

    -- Aggregate predictions
    local aggregated = self:_aggregatePredictions(predictions, self._weights)

    return aggregated
  end

  function ensemble_program:_aggregatePredictions(predictions, weights)
    if self._aggregation_strategy == "majority_vote" then
      return M._majorityVote(self, predictions)
    elseif self._aggregation_strategy == "weighted" then
      return M._weightedAggregation(self, predictions, weights)
    else
      return M._confidenceWeightedAggregation(self, predictions, weights)
    end
  end

  return ensemble_program
end

-- =============================================================================
-- Analysis Methods
-- =============================================================================

function M:GetEnsemble()
  return self._ensemble
end

function M:GetWeights()
  return self._weights
end

function M:GetBestScore()
  return self._best_score
end

function M:GetEnsembleSize()
  return #self._ensemble
end

function M:AnalyzeEnsemble()
  if #self._ensemble == 0 then
    return {
      size = 0,
      total_demonstrations = 0,
      avg_demonstrations = 0,
      diversity_score = 0
    }
  end

  local total_demos = 0
  local unique_demos = {}
  local sig_set = {}

  for _, member in ipairs(self._ensemble) do
    total_demos = total_demos + #member.demonstrations

    for _, demo in ipairs(member.demonstrations) do
      local sig = self:_demoSignature(demo)
      sig_set[sig] = true
    end
  end

  local unique_count = 0
  for _ in pairs(sig_set) do
    unique_count = unique_count + 1
  end

  return {
    size = #self._ensemble,
    total_demonstrations = total_demos,
    avg_demonstrations = total_demos / #self._ensemble,
    diversity_score = unique_count / total_demos
  }
end

return M
