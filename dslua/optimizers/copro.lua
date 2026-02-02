-- dslua/optimizers/copro.lua
-- COPRO: Coordinate Descent Prompt Optimization

local BaseOptimizer = require("dslua.optimizers.base")
local FewShot = require("dslua.modules.fewshot")

local M = {}
M.__index = M
setmetatable(M, {__index = BaseOptimizer})

-- =============================================================================
-- COPRO.new - Create COPRO optimizer
-- =============================================================================

function M.new(module, opts)
  opts = opts or {}

  -- Pass valset as dataset to parent for evaluation
  local parent_opts = {
    dataset = opts.valset or opts.dataset or {}
  }
  local self = BaseOptimizer.new(module, parent_opts)
  setmetatable(self, M)

  -- COPRO-specific options
  self._trainset = opts.trainset or {}
  self._valset = opts.valset or opts.dataset or {}
  self._max_rounds = opts.max_rounds or 10
  self._max_demonstrations = opts.max_demonstrations or 8
  self._candidates_per_round = opts.candidates_per_round or 5
  self._temperature = opts.temperature or 0.3
  self._early_stopping_patience = opts.early_stopping_patience or 3

  -- Tracking
  self._best_demos = {}
  self._best_score = 0
  self._history = {}

  return self
end

-- =============================================================================
-- Compile - Optimize program using COPRO
-- =============================================================================

function M:Compile(ctx, num_rounds)
  num_rounds = num_rounds or self._max_rounds

  if #self._trainset == 0 then
    -- Return base module with no demonstrations
    local empty_program = FewShot.new(self._module, {})
    return empty_program, {
      score = 0,
      num_demonstrations = 0,
      rounds = 0
    }
  end

  print("[COPRO] Starting compilation...")
  print(string.format("  Trainset size: %d", #self._trainset))
  print(string.format("  Valset size: %d", #self._valset))
  print(string.format("  Max rounds: %d", num_rounds))
  print(string.format("  Max demonstrations: %d", self._max_demonstrations))
  print(string.format("  Temperature: %.2f", self._temperature))

  -- Start with random subset
  local current_demos = self:_randomSubset(math.min(3, #self._trainset))
  self._best_demos = current_demos

  -- Evaluate initial configuration
  local current_score = 0
  if #self._valset > 0 then
    local current_program = FewShot.new(self._module, current_demos)
    current_score = self:Evaluate(ctx, current_program)
  end

  self._best_score = current_score
  print(string.format("  Initial score: %.4f with %d demos", current_score, #current_demos))

  local patience_counter = 0

  -- Coordinate descent: iteratively improve demonstrations
  for round = 1, num_rounds do
    print(string.format("\n  Round %d:", round))

    local improved = false

    -- Try different operations in each round
    local operations = {
      "add", "remove", "replace", "swap"
    }

    for _, operation in ipairs(operations) do
      local candidates = self:_generateCandidates(current_demos, operation)

      for _, candidate in ipairs(candidates) do
        local candidate_program = FewShot.new(self._module, candidate)
        local score = 0

        if #self._valset > 0 then
          score = self:Evaluate(ctx, candidate_program)
        else
          score = self:_heuristicScore(candidate)
        end

        -- Accept if better or with probability based on temperature
        local accept = false
        if score > current_score then
          accept = true
        elseif self._temperature > 0 then
          local delta = score - current_score
          local prob = math.exp(delta / self._temperature)
          accept = math.random() < prob
        end

        if accept then
          current_demos = candidate
          current_score = score
          improved = true

          if score > self._best_score then
            self._best_demos = candidate
            self._best_score = score
            print(string.format("    %s: New best score %.4f (%d demos)",
              operation, score, #candidate))
          end
        end
      end
    end

    -- Record history
    table.insert(self._history, {
      round = round,
      score = current_score,
      num_demos = #current_demos,
      improved = improved
    })

    -- Early stopping check
    if improved then
      patience_counter = 0
    else
      patience_counter = patience_counter + 1
      print(string.format("    No improvement (patience: %d/%d)",
        patience_counter, self._early_stopping_patience))

      if patience_counter >= self._early_stopping_patience then
        print("    Early stopping triggered")
        break
      end
    end

    -- Limit demonstrations
    if #current_demos >= self._max_demonstrations then
      print(string.format("    Reached max demonstrations (%d)", self._max_demonstrations))
      break
    end
  end

  -- Create best program
  local best_program = FewShot.new(self._module, self._best_demos)

  print(string.format("\n  Final score: %.4f", self._best_score))
  print(string.format("  Final demonstrations: %d", #self._best_demos))
  print("[COPRO] Compilation complete")

  return best_program, {
    score = self._best_score,
    num_demonstrations = #self._best_demos,
    demonstrations = self._best_demos,
    rounds = #self._history
  }
end

-- =============================================================================
-- Private Helper Methods
-- =============================================================================

function M:_randomSubset(size)
  -- Select random subset from trainset
  size = math.min(size, #self._trainset)

  local shuffled = {}
  for i = 1, #self._trainset do
    shuffled[i] = self._trainset[i]
  end

  -- Fisher-Yates shuffle
  for i = #shuffled, 2, -1 do
    local j = math.random(i)
    shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
  end

  local subset = {}
  for i = 1, size do
    subset[i] = shuffled[i]
  end

  return subset
end

function M:_generateCandidates(current_demos, operation)
  -- Generate candidate demonstration sets
  local candidates = {}

  if operation == "add" and #current_demos < self._max_demonstrations then
    -- Add new demonstrations
    local available = self:_getAvailableDemos(current_demos)

    for i = 1, math.min(self._candidates_per_round, #available) do
      local idx = math.random(1, #available)
      local new_demo = available[idx]

      local candidate = {}
      for _, demo in ipairs(current_demos) do
        table.insert(candidate, demo)
      end
      table.insert(candidate, new_demo)

      table.insert(candidates, candidate)

      -- Remove used
      table.remove(available, idx)
      if #available == 0 then
        break
      end
    end

  elseif operation == "remove" and #current_demos > 1 then
    -- Remove demonstrations
    for i = 1, math.min(self._candidates_per_round, #current_demos) do
      local remove_idx = math.random(1, #current_demos)

      local candidate = {}
      for j, demo in ipairs(current_demos) do
        if j ~= remove_idx then
          table.insert(candidate, demo)
        end
      end

      table.insert(candidates, candidate)
    end

  elseif operation == "replace" then
    -- Replace demonstrations
    local available = self:_getAvailableDemos(current_demos)

    for i = 1, math.min(self._candidates_per_round, #current_demos) do
      if #available > 0 then
        local replace_idx = math.random(1, #current_demos)
        local add_idx = math.random(1, #available)

        local candidate = {}
        for j, demo in ipairs(current_demos) do
          if j == replace_idx then
            candidate[j] = available[add_idx]
          else
            candidate[j] = demo
          end
        end

        table.insert(candidates, candidate)
      end
    end

  elseif operation == "swap" and #current_demos > 1 then
    -- Swap positions
    for i = 1, math.min(self._candidates_per_round, 3) do
      local idx1 = math.random(1, #current_demos)
      local idx2 = math.random(1, #current_demos)

      if idx1 ~= idx2 then
        local candidate = {}
        for j, demo in ipairs(current_demos) do
          candidate[j] = demo
        end

        -- Swap
        candidate[idx1], candidate[idx2] = candidate[idx2], candidate[idx1]

        table.insert(candidates, candidate)
      end
    end
  end

  return candidates
end

function M:_getAvailableDemos(current_demos)
  -- Get demos not in current set
  local current_set = {}
  for _, demo in ipairs(current_demos) do
    local sig = self:_demoSignature(demo)
    current_set[sig] = true
  end

  local available = {}
  for _, demo in ipairs(self._trainset) do
    local sig = self:_demoSignature(demo)
    if not current_set[sig] then
      table.insert(available, demo)
    end
  end

  return available
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

function M:_heuristicScore(demos)
  -- Heuristic score when no validation set
  -- Score based on diversity and coverage
  local diversity_score = 0
  local sig_set = {}

  for _, demo in ipairs(demos) do
    local sig = self:_demoSignature(demo)
    if not sig_set[sig] then
      sig_set[sig] = true
      diversity_score = diversity_score + 1
    end
  end

  -- Normalize by number of demos
  return diversity_score / #demos
end

-- =============================================================================
-- Analysis Methods
-- =============================================================================

function M:GetBestDemonstrations()
  return self._best_demos
end

function M:GetBestScore()
  return self._best_score
end

function M:GetHistory()
  return self._history
end

function M:AnalyzeOptimizationPath()
  if #self._history == 0 then
    return {
      total_rounds = 0,
      improved_rounds = 0,
      final_score = 0,
      score_improvement = 0
    }
  end

  local improved_count = 0
  for _, entry in ipairs(self._history) do
    if entry.improved then
      improved_count = improved_count + 1
    end
  end

  local initial_score = self._history[1].score
  local final_score = self._history[#self._history].score

  return {
    total_rounds = #self._history,
    improved_rounds = improved_count,
    final_score = final_score,
    initial_score = initial_score,
    score_improvement = final_score - initial_score,
    improvement_rate = improved_count / #self._history
  }
end

return M
