-- examples/mipro_optimizer_example.lua
-- MIPRO Optimizer Usage Example

local MIPRO = require("dslua.optimizers.mipro")
local Signature = require("dslua.core.signature")
local Field = require("dslua.core.field")
local Predict = require("dslua.modules.predict")

-- Example 1: Basic MIPRO usage for simple QA task
print("=== Example 1: Basic MIPRO Optimization ===")

-- Define the task signature
local signature = Signature.new(
  {Field.new("question")},
  {Field.new("answer")}
)

-- Create base module
local base_module = Predict.new(signature)

-- Training data (demonstrations)
local trainset = {
  {input = {question = "What is 2+2?"}, output = {answer = "4"}},
  {input = {question = "What is 3+3?"}, output = {answer = "6"}},
  {input = {question = "What is 5+5?"}, output = {answer = "10"}},
  {input = {question = "What is 4*3?"}, output = {answer = "12"}},
  {input = {question = "What is 10/2?"}, output = {answer = "5"}}
}

-- Validation data
local valset = {
  {input = {question = "What is 1+1?"}, output = {answer = "2"}},
  {input = {question = "What is 2*2?"}, output = {answer = "4"}},
  {input = {question = "What is 6/2?"}, output = {answer = "3"}}
}

-- Create MIPRO optimizer
local optimizer = MIPRO.new(base_module, {
  weights = {accuracy = 1.0}  -- Optimize for accuracy
})

-- Configure optimization
optimizer.num_trials = 10
optimizer.seed = 42
optimizer.verbose = true

-- Note: In real usage, you would provide an actual LLM context
-- local ctx = {
--   LLM = function()
--     return YourLLM()
--   end
-- }
--
-- local best_program, metrics = optimizer:Compile(trainset, valset)
--
-- print("Best score:", optimizer:GetBestScore())
-- print("Best accuracy:", optimizer:GetBestMetrics().accuracy)

print("Optimizer configured successfully")
print("  - Number of trials:", optimizer.num_trials)
print("  - Early stopping rounds:", optimizer.early_stopping_rounds)
print()

-- Example 2: Multi-objective optimization
print("=== Example 2: Multi-Objective Optimization ===")

local optimizer2 = MIPRO.new(base_module, {
  weights = {
    accuracy = 1.0,
    latency = -0.001  -- Penalize high latency
  }
})

optimizer2.num_trials = 15
optimizer2.seed = 42
optimizer2.verbose = true

print("Multi-objective optimizer configured")
print("  - Optimizing for: accuracy (positive), latency (negative)")
print()

-- Example 3: Custom metric function
print("=== Example 3: Custom Metric Function ===")

local custom_metric = function(results)
  -- Reward concise answers (shorter is better)
  local total_length = 0
  for _, result in ipairs(results) do
    if result.output and result.output.answer then
      total_length = total_length + #result.output.answer
    end
  end
  local avg_length = total_length / #results
  return 1.0 / (avg_length + 1)  -- Higher score for shorter answers
end

local optimizer3 = MIPRO.new(base_module, {
  weights = {custom_score = 1.0},
  metric_fn = custom_metric
})

optimizer3.num_trials = 8
optimizer3.seed = 42

print("Custom metric optimizer configured")
print("  - Metric: Conciseness (shorter answers preferred)")
print()

-- Example 4: Custom hyperparameter space
print("=== Example 4: Custom Hyperparameter Space ===")

local optimizer4 = MIPRO.new(base_module)

optimizer4:Configure({
  num_trials = 12,
  early_stopping_rounds = 3,
  hyperparameter_space = {
    num_demos = {type = "int", min = 2, max = 8},
    demo_selection = {type = "enum", values = {"random", "diverse"}},
    instruction_template = {type = "enum", values = {"basic", "detailed", "cot"}}
  }
})

print("Custom hyperparameter space configured:")
print("  - num_demos: 2 to 8")
print("  - demo_selection: random or diverse")
print("  - instruction_template: basic, detailed, or cot")
print()

-- Example 5: Accessing optimization results
print("=== Example 5: Accessing Results ===")

-- After running optimization (hypothetical):
-- local best_program = optimizer:GetBestProgram()
-- local best_score = optimizer:GetBestScore()
-- local best_metrics = optimizer:GetBestMetrics()
--
-- print("Best program:", best_program)
-- print("Best score:", best_score)
-- print("Validation accuracy:", best_metrics.accuracy)
-- print("Average latency:", best_metrics.avg_latency_ms, "ms")

print("API methods available:")
print("  - optimizer:GetBestProgram() - Returns optimized program")
print("  - optimizer:GetBestScore() - Returns optimization score")
print("  - optimizer:GetBestMetrics() - Returns full metrics")
print()

-- Example 6: Early stopping configuration
print("=== Example 6: Early Stopping ===")

local optimizer5 = MIPRO.new(base_module)
optimizer5.num_trials = 50
optimizer5.early_stopping_rounds = 5
optimizer5.seed = 42
optimizer5.verbose = true

print("Early stopping configured:")
print("  - Max trials: 50")
print("  - Stop if no improvement for: 5 trials")
print("  - Minimum trials before stopping: 5")
print()

print("=== All Examples Complete ===")
