-- dslua/optimizers/simba.lua
-- SIMBA: Similarity-Based Bootstrap Optimizer

local BaseOptimizer = require("dslua.optimizers.base")
local FewShot = require("dslua.modules.fewshot")

local M = {}
M.__index = M
setmetatable(M, {__index = BaseOptimizer})

-- =============================================================================
-- SIMBA.new - Create SIMBA optimizer
-- =============================================================================

function M.new(module, opts)
  opts = opts or {}

  -- Pass valset as dataset to parent for evaluation
  local parent_opts = {
    dataset = opts.valset or opts.dataset or {}
  }
  local self = BaseOptimizer.new(module, parent_opts)
  setmetatable(self, M)

  -- SIMBA-specific options
  self._trainset = opts.trainset or {}
  self._valset = opts.valset or opts.dataset or {}
  self._similarity_threshold = opts.similarity_threshold or 0.7
  self._diversity_bonus = opts.diversity_bonus or 0.1
  self._max_demonstrations = opts.max_demonstrations or 8
  self._temperature = opts.temperature or 0.7
  self._max_refinements = opts.max_refinements or 5

  -- Tracking
  self._selected_demos = {}
  self._similarity_scores = {}
  self._best_score = 0

  return self
end

-- =============================================================================
-- Compile - Optimize program using SIMBA
-- =============================================================================

function M:Compile(ctx, num_trials)
  num_trials = num_trials or 10

  if #self._trainset == 0 then
    -- Return base module with no demonstrations
    local empty_program = FewShot.new(self._module, {})
    return empty_program, {
      score = 0,
      num_demos = 0,
      demonstrations = {}
    }
  end

  print("[SIMBA] Starting compilation...")
  print(string.format("  Trainset size: %d", #self._trainset))
  print(string.format("  Valset size: %d", #self._valset))
  print(string.format("  Similarity threshold: %.2f", self._similarity_threshold))
  print(string.format("  Max demonstrations: %d", self._max_demonstrations))

  local best_program = nil
  local best_score = -1
  local best_demos = {}

  -- Step 1: Calculate pairwise similarities
  local similarities = self:_calculateSimilarities(self._trainset)

  -- Step 2: Try multiple diverse subsets
  for trial = 1, num_trials do
    -- Select diverse demonstrations
    local selected = self:_selectDiverseDemos(self._trainset, similarities)

    -- Create fewshot program with these demonstrations
    local program = FewShot.new(self._module, selected)

    -- Evaluate on validation set
    local score = 0
    if #self._valset > 0 then
      score = self:Evaluate(ctx, program)
    else
      score = 0  -- No validation set, use heuristics
    end

    if score > best_score then
      best_score = score
      best_program = program
      best_demos = selected
    end
  end

  -- Step 3: Refine best program with temperature-based search
  if #self._valset > 0 and #best_demos > 0 then
    local refined_program, refined_score = self:_refineWithTemperature(
      ctx, best_demos, best_program, best_score
    )

    if refined_score > best_score then
      best_program = refined_program
      best_score = refined_score
      print(string.format("  Refinement improved score to %.4f", best_score))
    end
  end

  -- Store tracking info
  self._selected_demos = best_demos
  self._similarity_scores = similarities
  self._best_score = best_score

  print(string.format("  Final score: %.4f", best_score))
  print(string.format("  Selected %d demonstrations", #best_demos))
  print("[SIMBA] Compilation complete")

  return best_program or FewShot.new(self._module, {}), {
    score = best_score,
    num_demos = #best_demos,
    demonstrations = best_demos
  }
end

-- =============================================================================
-- Private Helper Methods
-- =============================================================================

function M:_calculateSimilarities(dataset)
  -- Calculate pairwise similarities between examples
  local similarities = {}

  for i = 1, #dataset do
    similarities[i] = {}
    for j = 1, #dataset do
      if i == j then
        similarities[i][j] = 1.0
      else
        similarities[i][j] = self:_similarity(dataset[i], dataset[j])
      end
    end
  end

  return similarities
end

function M:_similarity(ex1, ex2)
  -- Calculate similarity between two examples
  local score = 0
  local fields = 0

  -- Compare input fields
  for k, v in pairs(ex1) do
    if k ~= "ctx" and type(v) == "string" and ex2[k] and type(ex2[k]) == "string" then
      local words1 = self:_tokenize(v)
      local words2 = self:_tokenize(ex2[k])

      -- Jaccard similarity
      local intersection = 0
      for w1, _ in pairs(words1) do
        if words2[w1] then
          intersection = intersection + 1
        end
      end

      local union = 0
      for _, _ in pairs(words1) do union = union + 1 end
      for _, _ in pairs(words2) do union = union + 1 end

      if union > 0 then
        score = score + (intersection / union)
        fields = fields + 1
      end
    end
  end

  -- Compare output fields if available
  if ex1.answer and ex2.answer then
    local ans1 = tostring(ex1.answer)
    local ans2 = tostring(ex2.answer)

    if ans1 == ans2 then
      score = score + 1.0
      fields = fields + 1
    else
      -- Partial similarity for answers
      local words1 = self:_tokenize(ans1)
      local words2 = self:_tokenize(ans2)

      local intersection = 0
      for w1, _ in pairs(words1) do
        if words2[w1] then
          intersection = intersection + 1
        end
      end

      local union = 0
      for _, _ in pairs(words1) do union = union + 1 end
      for _, _ in pairs(words2) do union = union + 1 end

      if union > 0 then
        score = score + (0.5 * intersection / union)
        fields = fields + 1
      end
    end
  end

  return fields > 0 and (score / fields) or 0
end

function M:_tokenize(text)
  local tokens = {}
  for word in text:gmatch("[%w]+") do
    tokens[word] = true
  end
  return tokens
end

function M:_selectDiverseDemos(dataset, similarities)
  -- Select diverse demonstrations using greedy algorithm
  local selected = {}
  local remaining = {}

  for i = 1, #dataset do
    table.insert(remaining, i)
  end

  -- Start with random example
  if #remaining > 0 then
    local first_idx = math.random(1, #remaining)
    table.insert(selected, remaining[first_idx])
    table.remove(remaining, first_idx)
  end

  -- Greedily add diverse examples
  while #selected < self._max_demonstrations and #remaining > 0 do
    local best_idx = nil
    local best_score = -1

    for _, idx in ipairs(remaining) do
      -- Calculate minimum similarity to already selected
      local min_sim = 1.0
      for _, sel_idx in ipairs(selected) do
        local sim = similarities[idx][sel_idx] or 0
        min_sim = math.min(min_sim, sim)
      end

      -- Diversity bonus: prefer examples with low similarity to selected
      local diversity_score = (1.0 - min_sim) + self._diversity_bonus

      if diversity_score > best_score then
        best_score = diversity_score
        best_idx = idx
      end
    end

    if best_idx then
      table.insert(selected, best_idx)

      -- Remove from remaining
      for i, idx in ipairs(remaining) do
        if idx == best_idx then
          table.remove(remaining, i)
          break
        end
      end
    else
      break
    end
  end

  -- Convert indices to examples
  local result = {}
  for _, idx in ipairs(selected) do
    table.insert(result, dataset[idx])
  end

  return result
end

function M:_refineWithTemperature(ctx, current_demos, current_program, current_score)
  -- Refine demonstrations using temperature-based stochastic search
  local best_program = current_program
  local best_score = current_score
  local best_demos = current_demos
  local improved = false

  for iteration = 1, self._max_refinements do
    -- Temperature decreases over iterations
    local temp = self._temperature * (1 - iteration / self._max_refinements)

    -- Try replacing one demo
    for replace_idx = 1, #current_demos do
      local candidate_demos = {}
      for i, demo in ipairs(current_demos) do
        if i ~= replace_idx then
          table.insert(candidate_demos, demo)
        end
      end

      -- Select random alternative
      local alt_idx = math.random(1, #self._trainset)
      table.insert(candidate_demos, replace_idx, self._trainset[alt_idx])

      -- Create candidate program
      local candidate_program = FewShot.new(self._module, candidate_demos)

      -- Evaluate candidate
      local score = self:Evaluate(ctx, candidate_program)

      -- Accept if better or with probability based on temperature
      local accept = false
      if score > best_score then
        accept = true
      elseif temp > 0 then
        local delta = score - best_score
        local prob = math.exp(delta / temp)
        accept = math.random() < prob
      end

      if accept then
        best_program = candidate_program
        best_demos = candidate_demos
        best_score = score
        improved = true
      end
    end
  end

  return best_program, best_score
end

-- =============================================================================
-- Analysis Methods
-- =============================================================================

function M:GetSimilarityMatrix()
  return self._similarity_scores
end

function M:GetSelectedDemos()
  return self._selected_demos
end

function M:GetBestScore()
  return self._best_score
end

function M:AnalyzeDiversity()
  if #self._selected_demos < 2 then
    return {
      avg_similarity = 1.0,
      min_similarity = 1.0,
      max_similarity = 1.0
    }
  end

  local total_sim = 0
  local count = 0
  local min_sim = 1.0
  local max_sim = 0

  for i = 1, #self._selected_demos do
    for j = i + 1, #self._selected_demos do
      local sim = self:_similarity(self._selected_demos[i], self._selected_demos[j])
      total_sim = total_sim + sim
      count = count + 1
      min_sim = math.min(min_sim, sim)
      max_sim = math.max(max_sim, sim)
    end
  end

  return {
    avg_similarity = count > 0 and (total_sim / count) or 1.0,
    min_similarity = min_sim,
    max_similarity = max_sim
  }
end

return M
