# ACE Phase 3: Pattern Mining and Outcome Feedback

**Date:** 2026-02-02
**Status:** Design Complete - Ready for Implementation
**Dependencies:** ACE Phase 2 (Learning from Demonstrations) ✅

## Overview

ACE Phase 3 extends learning beyond demonstrations by mining patterns from actual execution outcomes. Instead of only learning from expert demonstrations, ACE learns from its own execution experience, identifying which decisions lead to successful outcomes and which don't.

### Key Innovations

1. **Outcome-Based Learning** - Learn from success/failure of execution traces
2. **Pattern Mining** - Discover decision patterns that correlate with success
3. **Temporal Credit Assignment** - Distribute credit/blame across multi-step executions
4. **Online Learning** - Update weights during execution (not just offline training)
5. **Threshold Learning** - Adapt rule matching thresholds based on experience
6. **Continuous Salience** - Smooth salience values in [0,1] instead of binary {0,1}

## What Phase 3 Achieves

### Beyond Phase 2

| Aspect | Phase 2 | Phase 3 |
|--------|---------|---------|
| **Signal Source** | Expert demonstrations only | Execution outcomes + demonstrations |
| **Learning Mode** | Offline training only | Online + offline learning |
| **Credit Assignment** | Per-decision independent | Temporal (multi-step) |
| **Update Targets** | Rule weights only | Weights + thresholds |
| **Salience** | Binary {0,1} | Continuous [0,1] |
| **Rule Discovery** | Manual only | Automatic pattern mining |

### Capabilities

- ✅ **Self-improvement from experience** - ACE learns which strategies work for which tasks
- ✅ **Automatic rule discovery** - Mines patterns from successful executions
- ✅ **Adaptive thresholds** - Adjusts rule condition sensitivity based on outcomes
- ✅ **Continuous learning** - Updates weights during execution (not just batch training)
- ✅ **Outcome-aware credit** - Rewards decisions that contribute to successful task completion

## Architecture

### Components

```
ACE Phase 3 Architecture
├── Pattern Mining Module
│   ├── OutcomeTracker - Tracks execution outcomes
│   ├── PatternMiner - Discovers successful decision patterns
│   └── RuleGenerator - Creates new rules from patterns
├── Temporal Credit Module
│   ├── TraceAnalyzer - Analyzes multi-step execution traces
│   ├── CreditAssigner - Distributes credit across steps
│   └── OutcomeClassifier - Classifies success/failure
├── Online Learning Module
│   ├── OnlineUpdater - Updates weights during execution
│   ├── ExperienceBuffer - Stores execution experiences
│   └── ReplaySampler - Samples from experience for updates
└── Threshold Learning Module
    ├── ThresholdOptimizer - Adapts rule thresholds
    └── SensitivityAnalyzer - Analyzes threshold impact
```

### Data Flow

```
Execution Trace → Outcome Classification → Pattern Mining
                                              ↓
                                          Credit Assignment
                                              ↓
                                          Weight/Threshold Updates
                                              ↓
                                          New Rule Discovery
```

## Module 1: Outcome Tracking

### Purpose

Track execution outcomes and classify them as success/failure with confidence scores.

### Interface

```lua
-- dslua/agents/ace_outcome.lua
local M = {}

-- Classify execution outcome
-- @param trace: Execution trace with steps, final_result, error
-- @return: {success: boolean, confidence: number, reason: string}
function M.ClassifyOutcome(trace, opts)
    -- Success indicators:
    -- - No errors
    -- - Final result present and valid
    -- - Steps taken within reasonable bounds
    -- - Task-specific success criteria (optional callback)
end

-- Extract features from execution trace
-- @param trace: Execution trace
-- @return: Feature table for pattern mining
function M.ExtractFeatures(trace)
    -- Features:
    -- - Task type, complexity, entity count
    -- - Actions taken (sequence)
    -- - Tool usage (counts, types)
    -- - Confidence trajectory
    -- - Steps taken, duration
end

return M
```

### Success Criteria

**Default Success Indicators:**
1. No errors during execution
2. Final result present and non-empty
3. Steps taken ≤ max_steps
4. Confidence ≥ min_confidence (optional)

**Custom Success Criteria:**
```lua
custom_success_fn = function(trace)
    -- Domain-specific success logic
    -- e.g., for math problems: verify answer correctness
    -- e.g., for retrieval: check information relevance
    return boolean, confidence, reason
end
```

## Module 2: Pattern Mining

### Purpose

Discover decision patterns that correlate with successful outcomes.

### Interface

```lua
-- dslua/agents/ace_pattern_mining.lua
local M = {}

-- Mine patterns from execution traces
-- @param traces: Array of execution traces with outcomes
-- @param opts: Mining options
-- @return: Array of discovered patterns
function M.MinePatterns(traces, opts)
    -- Patterns include:
    -- - State features → Action mappings
    -- - Action sequences that lead to success
    -- - Feature combinations with high success correlation
    -- - Threshold values that distinguish success/failure
end

-- Convert pattern to rule format
-- @param pattern: Discovered pattern
-- @return: Rule table compatible with ACE
function M.PatternToRule(pattern)
    -- Generate rule with:
    -- - Conditions from pattern features
    -- - Action from pattern recommendation
    -- - Initial weight (confidence)
end

-- Score pattern quality
-- @param pattern: Pattern to evaluate
-- @param traces: Traces to validate against
-- @return: Quality score (0-1)
function M.ScorePattern(pattern, traces)
    -- Quality metrics:
    -- - Success rate (pattern use → success)
    -- - Coverage (how often pattern applies)
    -- - Specificity (not too general)
    -- - Stability (consistent across contexts)
end

return M
```

### Pattern Representation

```lua
{
    id = "pattern_001",
    state_features = {
        task_type = "math",
        complexity_range = {0.7, 1.0},
        tool_requirements = {"calculator"}
    },
    recommended_action = "USE_CALCULATOR",
    statistics = {
        success_count = 45,
        failure_count = 5,
        total_uses = 50,
        success_rate = 0.90
    },
    source_traces = {trace_id_1, trace_id_2, ...}
}
```

## Module 3: Temporal Credit Assignment

### Purpose

Distribute credit/blame across multi-step executions to fairly attribute outcomes to decisions.

### Interface

```lua
-- dslua/agents/ace_temporal_credit.lua
local M = {}

-- Assign credit to each decision in trace
-- @param trace: Execution trace with outcome
-- @param opts: Assignment options
-- @return: Array of {step_index, credit_score} pairs
function M.AssignCredit(trace, opts)
    -- Credit assignment methods:
    -- 1. Equal distribution - All steps get equal credit
    -- 2. Discounted future - Earlier steps get discounted credit
    -- 3. Action-based - Steps with key actions get more credit
    -- 4. TD-learning - Temporal difference learning
end

-- Propagate outcome back through trace
-- @param trace: Execution trace
-- @param outcome: Final outcome classification
-- @return: Credit assignments for each step
function M.PropagateOutcome(trace, outcome)
    -- Propagation methods:
    -- - Backpropagation through time (simplified)
    -- - Eligibility traces
    -- - Reward shaping
end

return M
```

### Credit Assignment Strategies

**Strategy 1: Equal Distribution**
```lua
-- Simple: Each step gets equal credit/blame
credit_per_step = outcome_credit / num_steps
```

**Strategy 2: Discounted Future**
```lua
-- Earlier steps get less credit (exponential decay)
credit[i] = outcome_credit * (gamma ^ (num_steps - i))
```

**Strategy 3: Action-Based**
```lua
-- Key actions (DECOMPOSE, SYNTHESIZE) get more credit
key_actions = {"DECOMPOSE", "SYNTHESIZE", "USE_CALCULATOR"}
multiplier = is_key_action(action) ? 1.5 : 0.5
```

## Module 4: Online Learning

### Purpose

Update weights during execution based on immediate feedback (not just batch training).

### Interface

```lua
-- dslua/agents/ace_online_learning.lua
local M = {}

-- Update weights from execution outcome
-- @param agent: ACE agent instance
-- @param trace: Execution trace
-- @param outcome: Classified outcome
-- @param opts: Update options
-- @return: Update metrics
function M.UpdateFromOutcome(agent, trace, outcome, opts)
    -- Update process:
    -- 1. Assign credit to each decision
    -- 2. For each decision step:
    --    a. If success: Increase weights of actions taken
    --    b. If failure: Decrease weights of actions taken
    -- 3. Apply bounded updates (respect max_weight_delta)
    -- 4. Track update metrics
end

-- Experience replay buffer
-- @param capacity: Max experiences to store
-- @return: Buffer object
function M.NewExperienceBuffer(capacity)
    -- Stores: {state, action, outcome, credit}
    -- Sampling: Random or prioritized by recentness/impact
end

return M
```

### Update Algorithm

```lua
-- For each execution step with credit c:
if outcome.success then
    -- Success: Increase weights of actions taken
    for rule in matching_rules(state, action) do
        delta = learning_rate * c * rule.salience
        weights[rule.key] = clamp(weights[rule.key] + delta, 0.1, 1.0)
    end
else
    -- Failure: Decrease weights of actions taken
    for rule in matching_rules(state, action) do
        delta = learning_rate * c * rule.salience
        weights[rule.key] = clamp(weights[rule.key] - delta, 0.1, 1.0)
    end
end
```

## Module 5: Threshold Learning

### Purpose

Adapt rule condition thresholds based on execution experience (currently hardcoded).

### Interface

```lua
-- dslua/agents/ace_threshold_learning.lua
local M = {}

-- Optimize thresholds from execution data
-- @param agent: ACE agent instance
-- @param traces: Execution traces
-- @param opts: Optimization options
-- @return: Optimized thresholds
function M.OptimizeThresholds(agent, traces, opts)
    -- For each rule with numeric conditions:
    -- 1. Collect condition values from traces
    -- 2. Find threshold that best separates success/failure
    -- 3. Validate on holdout set
    -- 4. Apply if improvement > min_improvement
end

-- Analyze threshold sensitivity
-- @param rule: Rule to analyze
-- @param traces: Execution traces
-- @return: Sensitivity analysis results
function M.AnalyzeSensitivity(rule, traces)
    -- Sensitivity metrics:
    -- - Success rate vs threshold value
    -- - Optimal threshold range
    -- - Threshold robustness (flat vs sharp)
end

return M
```

### Threshold Optimization

**Current State (Phase 2):**
```lua
-- Hardcoded thresholds
if complexity_estimate > 0.7 then
    -- Rule applies
end
```

**Phase 3: Learned Thresholds:**
```lua
-- Learned from experience
if complexity_estimate > learned_thresholds.complexity_high then
    -- Rule applies
end
```

## Module 6: Continuous Salience

### Purpose

Replace binary salience {0,1} with continuous salience [0,1] for smoother gradients.

### Interface

```lua
-- dslua/agents/ace_continuous_salience.lua
local M = {}

-- Compute continuous salience
-- @param rule: Rule to evaluate
-- @param state: Current state
-- @return: Salience in [0,1]
function M.ComputeSalience(rule, state)
    -- Distance-to-threshold salience:
    -- salience = 1.0 - (distance / threshold_range)
    -- Closer to threshold = higher salience
end

-- Partial matching salience
-- @param rule: Rule with multiple conditions
-- @param state: Current state
-- @return: Salience based on matched_conditions / total_conditions
function M.PartialMatchSalience(rule, state)
    -- Each condition contributes partial salience
    -- More matched conditions = higher salience
end

return M
```

## Integration with ACE

### New ACE Methods

```lua
-- dslua/agents/ace.lua ( additions)

-- Enable online learning during execution
function ACE:EnableOnlineLearning(opts)
    self._online_learning = true
    self._experience_buffer = OnlineLearning.NewExperienceBuffer(
        opts.buffer_size or 1000
    )
    self._online_opts = opts
end

-- Learn from execution outcome
function ACE:LearnFromOutcome(trace, outcome, opts)
    if not self._online_learning then
        error("Online learning not enabled. Call EnableOnlineLearning() first.")
    end

    local metrics = OnlineLearning.UpdateFromOutcome(
        self, trace, outcome, opts or self._online_opts
    )

    -- Store in experience buffer
    self._experience_buffer:push({
        trace = trace,
        outcome = outcome,
        metrics = metrics
    })

    return metrics
end

-- Mine patterns from execution history
function ACEMinePatterns(opts)
    local traces = self._experience_buffer:GetAll()
    local patterns = PatternMining.MinePatterns(traces, opts)

    -- Convert patterns to rules
    local new_rules = {}
    for _, pattern in ipairs(patterns) do
        if pattern.statistics.success_rate >= (opts.min_success_rate or 0.8) then
            table.insert(new_rules, PatternMining.PatternToRule(pattern))
        end
    end

    return new_rules
end

-- Optimize thresholds from experience
function ACE:OptimizeThresholds(traces, opts)
    local optimized = ThresholdLearning.OptimizeThresholds(
        self, traces, opts
    )

    -- Apply optimized thresholds
    for rule_name, threshold in pairs(optimized) do
        if self._rules[rule_name] then
            self._rules[rule_name].threshold = threshold
        end
    end

    return optimized
end
```

## Usage Example

```lua
local dslua = require("dslua")

-- Create ACE with online learning enabled
local ace = dslua.ACE.new(module, {
    rules = dslua.ACERules,
    learning_mode = "active",
    max_steps = 10
})

-- Enable online learning
ace:EnableOnlineLearning({
    buffer_size = 1000,
    learning_rate = 0.01,
    max_weight_delta = 0.01,
    credit_strategy = "discounted_future",
    gamma = 0.9
})

-- Execute task
local ctx = dslua.Context.new({llm = llm})
local result = ace:Execute(ctx, {question = "What is 15*27?"})

-- Classify outcome
local outcome = Outcome.ClassifyOutcome(result.trace, {
    min_confidence = 0.7,
    max_steps = 10
})

-- Learn from outcome (online update)
if outcome.success then
    local metrics = ace:LearnFromOutcome(result.trace, outcome)
    print("Learned from success:", metrics)
else
    local metrics = ace:LearnFromOutcome(result.trace, outcome)
    print("Learned from failure:", metrics)
end

-- Periodically mine patterns from experience
if ace._experience_buffer:Size() >= 100 then
    local new_rules = ace:MinePatterns({
        min_success_rate = 0.8,
        min_uses = 10,
        max_rules = 5
    })

    -- Add discovered rules to ACE
    for _, rule in ipairs(new_rules) do
        ace:AddRule(rule)
    end

    print("Discovered", #new_rules, "new rules from experience")
end

-- Optimize thresholds from execution history
local traces = ace._experience_buffer:GetAll()
local optimized = ace:OptimizeThresholds(traces, {
    validation_split = 0.2,
    min_improvement = 0.05
})

print("Optimized thresholds:", optimized)
```

## Testing Strategy

### Unit Tests

1. **Outcome Classification**
   - Test success/failure classification
   - Test confidence scoring
   - Test custom success criteria

2. **Pattern Mining**
   - Test pattern discovery from synthetic traces
   - Test pattern quality scoring
   - Test pattern-to-rule conversion

3. **Temporal Credit**
   - Test equal distribution credit assignment
   - Test discounted future credit assignment
   - Test action-based credit assignment

4. **Online Learning**
   - Test weight updates from success
   - Test weight updates from failure
   - Test experience buffer operations

5. **Threshold Learning**
   - Test threshold optimization on synthetic data
   - Test sensitivity analysis
    - Test threshold application

### Integration Tests

1. **End-to-End Learning Loop**
   - Execute task → classify outcome → update weights
   - Verify improvement over multiple executions

2. **Pattern Discovery**
   - Generate execution traces with known patterns
   - Verify pattern mining discovers them

3. **Threshold Adaptation**
   - Start with suboptimal thresholds
   - Verify learning improves thresholds

### Test Data

**Synthetic Traces:**
```lua
{
    task = {task_type = "math", complexity_estimate = 0.8},
    actions = {"USE_CALCULATOR", "VERIFY", "TERMINATE"},
    final_result = {answer = "405", confidence = 0.9},
    error = nil,
    steps_taken = 3,
    success = true
}
```

## Implementation Plan

### Phase 3.1: Outcome Tracking & Classification (1 day)
- [ ] Create `ace_outcome.lua`
- [ ] Implement `ClassifyOutcome()`
- [ ] Implement `ExtractFeatures()`
- [ ] Add unit tests

### Phase 3.2: Pattern Mining (2 days)
- [ ] Create `ace_pattern_mining.lua`
- [ ] Implement `MinePatterns()`
- [ ] Implement `PatternToRule()`
- [ ] Implement `ScorePattern()`
- [ ] Add unit tests

### Phase 3.3: Temporal Credit Assignment (1 day)
- [ ] Create `ace_temporal_credit.lua`
- [ ] Implement `AssignCredit()` (multiple strategies)
- [ ] Implement `PropagateOutcome()`
- [ ] Add unit tests

### Phase 3.4: Online Learning (1 day)
- [ ] Create `ace_online_learning.lua`
- [ ] Implement `UpdateFromOutcome()`
- [ ] Implement experience buffer
- [ ] Add unit tests

### Phase 3.5: Threshold Learning (1 day)
- [ ] Create `ace_threshold_learning.lua`
- [ ] Implement `OptimizeThresholds()`
- [ ] Implement `AnalyzeSensitivity()`
- [ ] Add unit tests

### Phase 3.6: Continuous Salience (1 day)
- [ ] Create `ace_continuous_salience.lua`
- [ ] Implement `ComputeSalience()` (distance-based)
- [ ] Implement `PartialMatchSalience()`
- [ ] Add unit tests

### Phase 3.7: ACE Integration (1 day)
- [ ] Add `EnableOnlineLearning()` to ACE
- [ ] Add `LearnFromOutcome()` to ACE
- [ ] Add `MinePatterns()` to ACE
- [ ] Add `OptimizeThresholds()` to ACE
- [ ] Add integration tests

### Phase 3.8: Documentation & Examples (1 day)
- [ ] Update README with Phase 3 usage
- [ ] Create example demonstrating online learning
- [ ] Update DESIGN.md with Phase 3 completion

**Total Estimated Time: 9 days**

## Success Criteria

1. **Functional Requirements**
   - ✅ ACE can learn from execution outcomes
   - ✅ Pattern mining discovers useful rules
   - ✅ Online learning improves performance over time
   - ✅ Threshold learning adapts to data

2. **Quality Requirements**
   - All tests passing (100% pass rate)
   - Test coverage >80% for new modules
   - Integration tests validate end-to-end learning

3. **Performance Requirements**
   - Online learning doesn't significantly slow execution
   - Pattern mining completes in reasonable time
   - Experience buffer has bounded memory usage

## Next Steps

After Phase 3 completion:
1. **ACE is feature-complete** for pattern mining and outcome feedback
2. **Evaluation** - Run comprehensive benchmarks
3. **Documentation** - Write usage guides and best practices
4. **Integration** - Consider integration with optimizers (MIPRO, etc.)

---

**Dependencies:**
- ACE Phase 1 (Decision Engine) ✅
- ACE Phase 2 (Learning from Demonstrations) ✅

**Blocked By:** None (ready to implement)

**Blocks:** Advanced features (multi-agent coordination, etc.)
