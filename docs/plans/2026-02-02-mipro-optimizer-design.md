# MIPRO Optimizer Implementation Plan

**Date:** 2026-02-02
**Status:** Design Complete - Ready for Implementation
**Priority:** 1 (Highest) - Critical for production prompt tuning
**Dependencies:** BootstrapFewShot optimizer ✅

## Overview

MIPRO (Multi-step Improvement with PRompt Optimization) is an advanced optimizer that uses TPE (Tree-structured Parzen Estimator) to automatically find optimal prompts and demonstration selections. Unlike BootstrapFewShot which uses random sampling, MIPRO uses Bayesian optimization to efficiently search the prompt space.

### Key Innovations

1. **TPE-based Optimization** - Uses Tree-structured Parzen Estimator for efficient search
2. **Multi-step Improvement** - Iteratively refines prompts based on validation performance
3. **Smart Demonstration Selection** - Chooses optimal subsets of training examples
4. **Hyperparameter Tuning** - Optimizes both prompt text and demonstrations simultaneously

### Why MIPRO Matters

| Feature | BootstrapFewShot | MIPRO |
|---------|-----------------|-------|
| **Search Strategy** | Random sampling | Bayesian optimization (TPE) |
| **Efficiency** | Requires many trials | Finds optimum faster |
| **Prompt Tuning** | Demonstrations only | Demonstrations + prompt instructions |
| **Performance** | Good baseline | State-of-the-art results |

## What MIPRO Achieves

### Beyond BootstrapFewShot

| Aspect | BootstrapFewShot | MIPRO |
|--------|-----------------|-------|
| **Demonstration Selection** | Random subsets | TPE-guided selection |
| **Prompt Instructions** | Fixed | Learned/optimized |
| **Trial Efficiency** | 10-20 trials | 5-10 trials |
| **Final Performance** | Good | Excellent (often 10-20% better) |

### Capabilities

- ✅ **Efficient search** - TPE finds good solutions in fewer trials
- ✅ **Prompt optimization** - Learns optimal instructions, not just demos
- ✅ **Multi-objective** - Balance accuracy, latency, cost
- ✅ **Adaptive** - Focuses search on promising regions
- ✅ **Reproducible** - Deterministic with seed

## Architecture

### Components

```
MIPRO Optimizer
├── TPE Module
│   ├── HyperparameterSpace - Define search space
│   ├── ParzenEstimator - Build probability models
│   ├── SampleCandidate - Generate promising candidates
│   └── UpdateObservations - Add trial results
├── PromptTuner Module
│   ├── InstructionOptimizer - Optimize prompt instructions
│   ├── DemoSelector - Select demonstration subsets
│   └── PromptBuilder - Assemble final prompt
├── Evaluator Module
│   ├── EvaluateProgram - Test program on validation set
│   ├── ComputeMetrics - Accuracy, latency, cost
│   └── MultiObjective - Weighted scoring
└── TrialHistory Module
    ├── RecordTrial - Store trial results
    ├── BestProgram - Track best configuration
    └── ConvergenceCheck - Early stopping
```

### Data Flow

```
Initial Program + Training Data
         ↓
    TPE Loop (num_trials)
         ↓
  1. Sample hyperparameters (demos, instruction)
         ↓
  2. Build candidate program
         ↓
  3. Evaluate on validation set
         ↓
  4. Update TPE models
         ↓
  5. Track best program
         ↓
Return optimized program
```

## Module 1: TPE (Tree-structured Parzen Estimator)

### Purpose

Efficiently search hyperparameter space using Bayesian optimization with Tree-structured Parzen Estimator.

### Algorithm Overview

TPE models two distributions:
- **l(x)** - Likelihood of x given good performance (top 25%)
- **g(x)** - Likelihood of x given poor performance (bottom 75%)

Acquisition function: `EI(x) = (γ - x) / l(x) * g(x)`

Where γ is a threshold (e.g., 75th percentile of observed scores).

### Interface

```lua
-- dslua/optimizers/mipro_tpe.lua
local M = {}

-- Create TPE optimizer
-- @param space: Hyperparameter space definition
-- @param opts: TPE options
-- @return: TPE optimizer object
function M.new(space, opts)
    -- space: {
    --   num_demos = {type = "int", min = 1, max = 10},
    --   instruction_type = {type = "enum", values = {"basic", "detailed", "cot"}}
    -- }
end

-- Sample next candidate
-- @param observations: Previous trials {{params, score}, ...}
-- @return: Candidate hyperparameters
function M.SampleCandidate(observations)
    -- 1. Split observations into good (top 25%) and poor (bottom 75%)
    -- 2. Build l(x) model from good observations
    -- 3. Build g(x) model from poor observations
    -- 4. Maximize Expected Improvement (EI) acquisition function
    -- 5. Return best candidate
end

-- Update observations with new trial
-- @param observations: Existing observations
-- @param params: Trial hyperparameters
-- @param score: Trial score
-- @return: Updated observations
function M.UpdateObservations(observations, params, score)
    table.insert(observations, {params = params, score = score})
    return observations
end

return M
```

### Hyperparameter Types

```lua
-- Integer parameter (e.g., number of demonstrations)
num_demos = {type = "int", min = 1, max = 10}

-- Categorical parameter (e.g., instruction type)
instruction_type = {type = "enum", values = {"basic", "detailed", "cot"}}

-- Continuous parameter (e.g., temperature)
temperature = {type = "float", min = 0.0, max = 1.0}
```

## Module 2: PromptTuner

### Purpose

Optimize prompt instructions and demonstration selections based on TPE recommendations.

### Interface

```lua
-- dslua/optimizers/mipro_prompt_tuner.lua
local M = {}

-- Optimize prompt from hyperparameters
-- @param base_program: Base module to optimize
-- @param hyperparams: TPE-chosen hyperparameters
-- @param trainset: Training demonstrations
-- @return: Optimized program with FewShot
function M.OptimizePrompt(base_program, hyperparams, trainset)
    -- 1. Select demonstrations based on hyperparams
    local demos = M._selectDemos(trainset, hyperparams)

    -- 2. Generate instruction based on hyperparams
    local instruction = M._generateInstruction(hyperparams)

    -- 3. Create FewShot program
    local fewshot = FewShot.new(base_program, demos)

    -- 4. Update instruction if provided
    if instruction then
        fewshot._signature:_instruction = instruction
    end

    return fewshot
end

-- Select demonstration subset
function M._selectDemos(trainset, hyperparams)
    local num_demos = hyperparams.num_demos
    local selection_strategy = hyperparams.demo_selection or "random"

    if selection_strategy == "random" then
        return M._randomSubset(trainset, num_demos)
    elseif selection_strategy == "diverse" then
        return M._diverseSubset(trainset, num_demos)
    elseif selection_strategy == "similar" then
        return M._similarSubset(trainset, num_demos)
    end
end

-- Generate instruction from template
function M._generateInstruction(hyperparams)
    local template = hyperparams.instruction_template or "default"

    if template == "basic" then
        return "Answer accurately."
    elseif template == "detailed" then
        return "Think step by step and provide detailed reasoning."
    elseif template == "cot" then
        return "Show your work and explain each step."
    end

    return nil
end

return M
```

### Demonstration Selection Strategies

**Random:** Uniform random sampling (baseline)

**Diverse:** Maximize diversity in selected demos
```lua
function M._diverseSubset(trainset, k)
    -- Greedy diversity sampling:
    -- 1. Start with random demo
    -- 2. Iteratively add demos most different from selected
    -- 3. Use embedding similarity or feature distance
end
```

**Similar:** Select demos similar to validation queries
```lua
function M._similarSubset(trainset, k, val_query)
    -- Find k demos most similar to typical validation queries
    -- Useful for task-specific demonstration
end
```

## Module 3: Evaluator

### Purpose

Evaluate candidate programs on validation set and compute metrics.

### Interface

```lua
-- dslua/optimizers/mipro_evaluator.lua
local M = {}

-- Evaluate program on validation set
-- @param program: Candidate program to test
-- @param valset: Validation data
-- @param ctx: Context with LLM
-- @param opts: Evaluation options
-- @return: Metrics table
function M.EvaluateProgram(program, valset, ctx, opts)
    local results = {}
    local total_correct = 0

    for _, example in ipairs(valset) do
        local result = program:Process(ctx, example.input)

        local correct = M._checkAccuracy(result, example.output)
        if correct then
            total_correct = total_correct + 1
        end

        table.insert(results, {
            output = result,
            expected = example.output,
            correct = correct,
            latency_ms = result.latency_ms or 0
        })
    end

    -- Compute metrics
    local metrics = {
        accuracy = total_correct / #valset,
        total_examples = #valset,
        correct_count = total_correct,
        results = results
    }

    -- Additional metrics if provided
    if opts.metric_fn then
        metrics.custom_score = opts.metric_fn(results)
    end

    return metrics
end

-- Multi-objective scoring
-- @param metrics: Evaluation metrics
-- @param weights: Objective weights
-- @return: Composite score
function M.ComputeScore(metrics, weights)
    weights = weights or {accuracy = 1.0}

    local score = 0
    local total_weight = 0

    for key, weight in pairs(weights) do
        if metrics[key] then
            score = score + (metrics[key] * weight)
            total_weight = total_weight + weight
        end
    end

    return score / math.max(total_weight, 1)
end

return M
```

## Module 4: MIPRO Main Optimizer

### Purpose

Orchestrate TPE-based optimization loop.

### Interface

```lua
-- dslua/optimizers/mipro.lua
local M = {}
M.__index = M

-- Create MIPRO optimizer
-- @param module: Base module to optimize
-- @param opts: Optimizer options
-- @return: MIPRO optimizer instance
function M.new(module, opts)
    opts = opts or {}

    local self = {
        _module = module,
        _trainset = opts.trainset or {},
        _valset = opts.valset or {},
        _num_trials = opts.num_trials or 10,
        _space = opts.space or M._defaultSpace(),
        _seed = opts.seed or 42,

        -- TPE components
        _tpe = TPE,
        _prompt_tuner = PromptTuner,
        _evaluator = Evaluator,

        -- Trial history
        _observations = {},
        _best_score = -math.huge,
        _best_program = nil
    }

    setmetatable(self, M)
    return self
end

-- Compile optimized program using TPE
-- @param ctx: Context with LLM
-- @param num_trials: Number of trials (override)
-- @return: Optimized program
function M:Compile(ctx, num_trials)
    num_trials = num_trials or self._num_trials

    for trial = 1, num_trials do
        -- 1. Sample candidate hyperparameters
        local hyperparams = TPE.SampleCandidate(self._observations)

        -- 2. Build candidate program
        local candidate = PromptTuner.OptimizePrompt(
            self._module,
            hyperparams,
            self._trainset
        )

        -- 3. Evaluate on validation set
        local metrics = Evaluator.EvaluateProgram(
            candidate,
            self._valset,
            ctx,
            {metric_fn = self._metric_fn}
        )

        local score = Evaluator.ComputeScore(metrics, self._weights)

        -- 4. Update observations
        self._observations = TPE.UpdateObservations(
            self._observations,
            hyperparams,
            score
        )

        -- 5. Track best program
        if score > self._best_score then
            self._best_score = score
            self._best_program = candidate
            self._best_metrics = metrics
        end

        -- 6. Early stopping check
        if self:_shouldStop(trial, num_trials) then
            break
        end
    end

    return self._best_program
end

-- Define default hyperparameter space
function M._defaultSpace()
    return {
        num_demos = {type = "int", min = 1, max = 10},
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

-- Check early stopping criteria
function M:_shouldStop(trial, max_trials)
    -- Stop if no improvement for 3 trials
    if trial > 5 then
        local recent_best = -math.huge
        for i = math.max(1, #self._observations - 2), #self._observations do
            local score = self._observations[i].score
            if score > recent_best then
                recent_best = score
            end
        end

        if recent_best <= self._best_score then
            return true  -- No improvement in last 3 trials
        end
    end

    return false
end

return M
```

## Usage Example

```lua
local dslua = require("dslua")

-- Prepare training data
local trainset = {
    {input = {question = "2+2"}, output = {answer = "4"}},
    {input = {question = "3+3"}, output = {answer = "6"}},
    {input = {question = "5+5"}, output = {answer = "10"}},
    -- ... 20-50 examples
}

local valset = {
    {input = {question = "4+4"}, output = {answer = "8"}},
    {input = {question = "7+7"}, output = {answer = "14"}},
    -- ... 5-10 examples
}

-- Create base module
local signature = dslua.Signature.new(
    {dslua.Field.new("question")},
    {dslua.Field.new("answer")}
)
local module = dslua.Predict.new(signature)

-- Create MIPRO optimizer
local mipro = dslua.MIPRO.new(module, {
    trainset = trainset,
    valset = valset,
    num_trials = 10,
    seed = 42
})

-- Compile optimized program
local ctx = dslua.Context.new({llm = llm})
local optimized = mipro:Compile(ctx, 10)

-- Use optimized program
local result = optimized:Process(ctx, {question = "15*15"})
print(result.answer)  -- Should be improved accuracy
```

## Implementation Plan

### Phase 1: TPE Module (2 days)
- [ ] Create `mipro_tpe.lua`
- [ ] Implement `SampleCandidate()` with TPE algorithm
- [ ] Implement `UpdateObservations()`
- [ ] Add unit tests

### Phase 2: PromptTuner Module (1 day)
- [ ] Create `mipro_prompt_tuner.lua`
- [ ] Implement demonstration selection strategies
- [ ] Implement instruction generation
- [ ] Add unit tests

### Phase 3: Evaluator Module (1 day)
- [ ] Create `mipro_evaluator.lua`
- [ ] Implement `EvaluateProgram()`
- [ ] Implement `ComputeScore()` for multi-objective
- [ ] Add unit tests

### Phase 4: MIPRO Main (1 day)
- [ ] Create `mipro.lua` with Compile() method
- [ ] Implement optimization loop
- [ ] Add early stopping
- [ ] Add integration tests

### Phase 5: Testing & Examples (1 day)
- [ ] End-to-end integration tests
- [ ] Benchmark vs BootstrapFewShot
- [ ] Create usage examples
- [ ] Update documentation

**Total Estimated Time: 6 days**

## Testing Strategy

### Unit Tests

1. **TPE Module**
   - Test candidate sampling with synthetic observations
   - Test observation updates
   - Test different hyperparameter types

2. **PromptTuner**
   - Test demo selection strategies
   - Test instruction generation
   - Test FewShot program creation

3. **Evaluator**
   - Test accuracy computation
   - Test multi-objective scoring
   - Test metric functions

### Integration Tests

1. **Optimization Loop**
   - Full MIPRO:Compile() on synthetic task
   - Verify improvement over baseline
   - Verify best program selection

2. **Comparison**
   - MIPRO vs BootstrapFewShot on same task
   - Measure trial efficiency
   - Compare final accuracy

### Benchmark Tests

```lua
-- Test on GSM8K (grade school math)
local mipro = MIPRO.new(module, {
    trainset = gsm8k_train,
    valset = gsm8k_val,
    num_trials = 10
})

local mipro_program = mipro:Compile(ctx, 10)
local mipro_accuracy = evaluate(mipro_program, test_set)

-- Compare with BootstrapFewShot
local bootstrap = BootstrapFewShot.new(module, {
    trainset = gsm8k_train,
    valset = gsm8k_val,
    max_bootstraps = 10
})

local bs_program = bootstrap:Compile(ctx, 10)
local bs_accuracy = evaluate(bs_program, test_set)

-- MIPRO should achieve 10-20% better accuracy
print("MIPRO:", mipro_accuracy)
print("BootstrapFewShot:", bs_accuracy)
```

## Success Criteria

1. **Functional Requirements**
   - ✅ MIPRO finds better prompts than random sampling
   - ✅ TPE efficiently searches hyperparameter space
   - ✅ Optimization converges in <10 trials
   - ✅ Supports multiple hyperparameter types

2. **Quality Requirements**
   - All tests passing (100% pass rate)
   - Test coverage >80%
   - Integration tests validate end-to-end flow

3. **Performance Requirements**
   - 10-20% accuracy improvement over BootstrapFewShot
   - Convergence in 5-10 trials (vs 15-20 for random)
   - No memory leaks in trial loop

## Hyperparameter Space

### Default Space

```lua
{
    -- Demonstration selection
    num_demos = {type = "int", min = 1, max = 10},
    demo_selection = {
        type = "enum",
        values = {"random", "diverse", "similar"}
    },

    -- Instruction tuning
    instruction_template = {
        type = "enum",
        values = {"none", "basic", "detailed", "cot"}
    },

    -- Advanced (optional)
    temperature = {type = "float", min = 0.0, max = 1.0},
    max_tokens = {type = "int", min = 100, max = 2000}
}
```

### Custom Space

Users can provide custom hyperparameter spaces:

```lua
local custom_space = {
    num_demos = {type = "int", min = 5, max = 20},
    demo_selection = {type = "enum", values = {"diverse", "semantic"}},
    instruction_template = {
        type = "enum",
        values = {"concise", "standard", "verbose"}
    },
    temperature = {type = "float", min = 0.0, max = 2.0}
}

local mipro = MIPRO.new(module, {
    trainset = trainset,
    valset = valset,
    space = custom_space
})
```

## Next Steps

After MIPRO implementation:
1. **Evaluate** on benchmark tasks (GSM8K, BBH, etc.)
2. **Compare** with BootstrapFewShot efficiency
3. **Document** best practices and hyperparameter tuning
4. **Integrate** with ACE for end-to-end optimization

---

**Dependencies:**
- BootstrapFewShot optimizer ✅
- FewShot module ✅
- Core modules (Predict, Signature, etc.) ✅

**Blocked By:** None (ready to implement)

**Blocks:** Advanced features (multi-objective optimization, constraints)
