-- dslua/optimizers/mipro_prompt_tuner.lua
-- MIPRO PromptTuner - Build candidate programs from hyperparameters

local M = {}
local FewShot = require("dslua.modules.fewshot")

-- =============================================================================
-- OptimizePrompt - Build candidate program from hyperparameters
-- =============================================================================

function M.OptimizePrompt(base_module, hyperparams, trainset)
  -- 1. Select demonstrations based on hyperparams
  local demos = M._selectDemos(
    trainset,
    hyperparams.num_demos or 3,
    hyperparams.demo_selection or "random"
  )

  -- 2. Generate instruction from template
  local instruction = M._generateInstruction(hyperparams)

  -- 3. Create FewShot program
  local program = FewShot.new(base_module, demos)

  -- 4. Update instruction if provided
  if instruction and program._signature then
    program._signature._instruction = instruction
  end

  return program
end

-- =============================================================================
-- _selectDemos - Select demonstration subset
-- =============================================================================

function M._selectDemos(trainset, num_demos, strategy, opts)
  opts = opts or {}

  if strategy == "random" then
    return M._randomSubset(trainset, num_demos, opts)
  elseif strategy == "diverse" then
    return M._diverseSubset(trainset, num_demos, opts)
  elseif strategy == "similar" then
    return M._similarSubset(trainset, num_demos, opts)
  else
    -- Default to random
    return M._randomSubset(trainset, num_demos, opts)
  end
end

function M._randomSubset(trainset, k, opts)
  k = math.min(k, #trainset)
  local indices = {}

  -- Use seed if provided for reproducibility
  if opts.seed then
    math.randomseed(opts.seed)
  end

  -- Generate k random indices
  while #indices < k do
    local idx = math.random(1, #trainset)
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

  -- Collect selected demos
  local selected = {}
  for _, idx in ipairs(indices) do
    table.insert(selected, trainset[idx])
  end

  return selected
end

function M._diverseSubset(trainset, k, opts)
  k = math.min(k, #trainset)
  local selected = {}
  local used = {}

  -- Greedy diversity sampling
  for i = 1, k do
    local best_idx = nil
    local best_score = -math.huge

    for idx, example in ipairs(trainset) do
      if not used[idx] then
        -- Compute diversity score (inverse of similarity to selected)
        local score = M._computeDiversity(example, selected)
        if score > best_score then
          best_score = score
          best_idx = idx
        end
      end
    end

    if best_idx then
      table.insert(selected, trainset[best_idx])
      used[best_idx] = true
    end
  end

  return selected
end

function M._similarSubset(trainset, k, opts)
  -- Select demos most similar to each other (for focused learning)
  k = math.min(k, #trainset)
  local selected = {}
  local used = {}

  -- Start with random demo
  if opts.seed then
    math.randomseed(opts.seed)
  end

  local first_idx = math.random(1, #trainset)
  table.insert(selected, trainset[first_idx])
  used[first_idx] = true

  -- Select demos most similar to already selected
  for i = 2, k do
    local best_idx = nil
    local best_score = -math.huge

    for idx, example in ipairs(trainset) do
      if not used[idx] then
        -- Compute similarity score to selected demos
        local score = M._computeSimilarity(example, selected)
        if score > best_score then
          best_score = score
          best_idx = idx
        end
      end
    end

    if best_idx then
      table.insert(selected, trainset[best_idx])
      used[best_idx] = true
    end
  end

  return selected
end

-- =============================================================================
-- _generateInstruction - Generate instruction from template
-- =============================================================================

function M._generateInstruction(hyperparams)
  local template = hyperparams.instruction_template or "none"

  if template == "none" then
    return nil
  elseif template == "basic" then
    return "Answer accurately."
  elseif template == "detailed" then
    return "Think step by step and provide detailed reasoning for your answer."
  elseif template == "cot" then
    return "Show your work and explain each step in detail."
  else
    return nil
  end
end

-- =============================================================================
-- Private helper functions
-- =============================================================================

function M._computeDiversity(example, selected)
  -- Higher score = more diverse from selected
  -- Diversity = 1 / average similarity to selected
  if #selected == 0 then
    return 1.0
  end

  local total_similarity = 0
  for _, sel in ipairs(selected) do
    local sim = M._computeExampleSimilarity(example, sel)
    total_similarity = total_similarity + sim
  end

  local avg_similarity = total_similarity / #selected
  return 1.0 / (avg_similarity + 0.001)  -- Avoid division by zero
end

function M._computeSimilarity(example, selected)
  -- Higher score = more similar to selected demos
  -- Similarity = average similarity to selected
  if #selected == 0 then
    return 0.0
  end

  local total_similarity = 0
  for _, sel in ipairs(selected) do
    local sim = M._computeExampleSimilarity(example, sel)
    total_similarity = total_similarity + sim
  end

  return total_similarity / #selected
end

function M._computeExampleSimilarity(ex1, ex2)
  -- Simple similarity based on input length difference
  local input1 = ex1.input.question or ""
  local input2 = ex2.input.question or ""

  local len1 = #input1
  local len2 = #input2

  local max_len = math.max(len1, len2)
  if max_len == 0 then
    return 1.0
  end

  local diff = math.abs(len1 - len2) / max_len
  return 1.0 - diff  -- Higher = more similar length
end

return M
