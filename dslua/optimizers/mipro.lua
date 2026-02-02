-- dslua/optimizers/mipro.lua
-- MIPRO: Multi-step Improvement with PRompt Optimization
-- TPE-based prompt optimizer for DSPy programs

local M = {}
local TPE = require("dslua.optimizers.mipro_tpe")
local PromptTuner = require("dslua.optimizers.mipro_prompt_tuner")
local Evaluator = require("dslua.optimizers.mipro_evaluator")

-- =============================================================================
-- MIPRO.new - Create new MIPRO optimizer
-- =============================================================================

function M.new(base_module, metric_opts)
  local self = {
    base_module = base_module,
    metric_opts = metric_opts or {},
    hyperparameter_space = M._defaultHyperparameterSpace(),
    num_trials = 20,
    early_stopping_rounds = 5,
    gamma = 0.25,  -- Top 25% for good observations
    best_program = nil,
    best_score = -math.huge,
    best_metrics = nil,
    seed = nil,
    verbose = false
  }
  setmetatable(self, {__index = M})
  return self
end

-- =============================================================================
-- Compile - Optimize program using TPE-based search
-- =============================================================================

function M:Compile(trainset, valset, opts)
  opts = opts or {}

  -- Merge options with defaults
  for key, val in pairs(opts) do
    self[key] = val
  end

  -- Set random seed if provided
  if self.seed then
    math.randomseed(self.seed)
  end

  -- Initialize observations
  local observations = {}
  local no_improvement_count = 0
  local prev_best_score = -math.huge

  -- Log start
  if self.verbose then
    print("MIPRO: Starting optimization with " .. self.num_trials .. " trials")
  end

  -- Main optimization loop
  for trial = 1, self.num_trials do
    -- 1. Sample candidate hyperparameters using TPE
    local candidate_hyperparams = TPE.SampleCandidate(
      observations,
      self.hyperparameter_space,
      {seed = self.seed and math.floor(self.seed + trial) or nil}
    )

    -- 2. Build candidate program from hyperparameters
    local candidate_program = PromptTuner.OptimizePrompt(
      self.base_module,
      candidate_hyperparams,
      trainset
    )

    -- 3. Evaluate candidate on validation set
    local metrics = Evaluator.EvaluateProgram(
      candidate_program,
      valset,
      self._buildContext(),
      self.metric_opts
    )

    -- 4. Compute multi-objective score
    local score = Evaluator.ComputeScore(
      metrics,
      self.metric_opts.weights or {accuracy = 1.0}
    )

    -- 5. Update observations
    observations = TPE.UpdateObservations(
      observations,
      candidate_hyperparams,
      score
    )

    -- 6. Update best program
    if score > self.best_score then
      self.best_score = score
      self.best_program = candidate_program
      self.best_metrics = metrics
      no_improvement_count = 0

      if self.verbose then
        print(string.format("Trial %d: New best score %.4f (accuracy: %.4f)",
          trial, score, metrics.accuracy or 0))
      end
    else
      no_improvement_count = no_improvement_count + 1

      if self.verbose then
        print(string.format("Trial %d: Score %.4f (accuracy: %.4f) [no improvement]",
          trial, score, metrics.accuracy or 0))
      end
    end

    -- 7. Check for early stopping
    if M._shouldStopEarly(self, no_improvement_count, trial) then
      if self.verbose then
        print(string.format("MIPRO: Early stopping at trial %d", trial))
      end
      break
    end
  end

  -- Log completion
  if self.verbose then
    print(string.format("MIPRO: Optimization complete. Best score: %.4f", self.best_score))
  end

  return self.best_program, self.best_metrics
end

-- =============================================================================
-- GetBestProgram - Retrieve best program found during optimization
-- =============================================================================

function M:GetBestProgram()
  return self.best_program
end

-- =============================================================================
-- GetBestScore - Retrieve best score found during optimization
-- =============================================================================

function M:GetBestScore()
  return self.best_score
end

-- =============================================================================
-- GetBestMetrics - Retrieve best metrics found during optimization
-- =============================================================================

function M:GetBestMetrics()
  return self.best_metrics
end

-- =============================================================================
-- Private helper methods
-- =============================================================================

function M._defaultHyperparameterSpace()
  return {
    num_demos = {
      type = "int",
      min = 1,
      max = 16
    },
    demo_selection = {
      type = "enum",
      values = {"random", "diverse", "similar"}
    },
    instruction_template = {
      type = "enum",
      values = {"none", "basic", "detailed", "cot"}
    }
  }
end

function M._buildContext()
  -- Return a mock context that will be provided by the caller
  -- The actual context should have an LLM() function
  return {
    LLM = function()
      return nil  -- Will be set during evaluation
    end
  }
end

function M._shouldStopEarly(self, no_improvement_count, current_trial)
  -- Don't stop if we haven't done minimum trials
  if current_trial < 5 then
    return false
  end

  -- Stop if no improvement for early_stopping_rounds
  if no_improvement_count >= self.early_stopping_rounds then
    return true
  end

  return false
end

-- =============================================================================
-- Configure - Update optimizer configuration
-- =============================================================================

function M:Configure(opts)
  for key, val in pairs(opts) do
    if key == "hyperparameter_space" then
      -- Merge with existing space
      for k, v in pairs(val) do
        self.hyperparameter_space[k] = v
      end
    else
      self[key] = val
    end
  end
  return self
end

return M
