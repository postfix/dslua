# ACE Phase 2 Integration Design

**Status:** Design Complete | Ready for Implementation

**Created:** 2026-02-01

**Goal:** Integrate validated POC learning algorithm into full ACE system with complete training pipeline.

---

## Executive Summary

This design integrates the ACE Phase 2 POC (validated learning algorithm) into the production ACE system. The integration refactors ACE's existing decision-making into pure functions usable by both execution and learning, adds weight persistence (JSON), demo loading/validation (ACE trace format), and multi-epoch training with early stopping.

**Key Characteristics:**
- **Unified Decision Primitives:** Single set of pure functions for execution and learning
- **Full Training Pipeline:** Demo loading → Train/val split → Multi-epoch learning → Early stopping → Weight export
- **ACE Trace Format:** Rich demo files capturing full execution state (task/self/history layers)
- **JSON Persistence:** Human-readable weight files for inspection and version control
- **Production Ready:** Comprehensive tests, error handling, determinism guarantees

---

## Architecture

### Overview

**Approach:** Refactor ACE's existing decision-making into pure functions that can be used by both the execution loop (Phase 1) and the learning algorithm (Phase 2). This creates a unified decision primitive with no code duplication.

**Data Flow:**

**Execution:**
```
Input → State → Matching Rules → Score → Select Action → Execute
```

**Learning:**
```
Demo Trace → Extract Decisions → For Each Decision:
  Compute Scores → Find Competitors → Update Weights
```

**Training:**
```
Load Demos → Train/Validate Split → For Each Epoch:
  Train on Train Set → Validate on Val Set → Check Early Stopping → Export Weights
```

### File Structure

```
dslua/agents/
  ace.lua              # Main ACE with learning methods
  ace_decision.lua     # Pure decision functions (extracted)
  ace_learning.lua     # Phase2Learner integrated
  ace_rules.lua        # Default rules (existing)
  ace_training.lua     # Training loop and demo loading
  ace_persistence.lua  # Weight export/load (JSON)

specs/agents/
  ace_decision_spec.lua      # Decision function tests
  ace_learning_spec.lua      # Learning algorithm tests
  ace_persistence_spec.lua   # Persistence tests
  ace_training_spec.lua      # Training loop tests
```

---

## Components

### ace_decision.lua - Pure Decision Functions

Extracts ACE's decision primitives into stateless pure functions:

```lua
local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}
local EPS = 1e-9

function NormalizeState(snapshot)
  -- Apply defaults to optional fields in task/self/history layers
  -- Returns: {task = {...}, self = {...}, history = {...}}
end

function FindMatchingRules(state, action, rules, weights)
  -- Returns: {{rule, weight, salience, key}, ...}
  -- Weight resolution: weights[key] or rule.default_weight
end

function ComputeSalience(rule, state, opts)
  -- Binary mode: 0 or 1
  -- Returns: salience, {mode, coerced, raw}
end

function ScoreActions(state, rules, weights, ACTIONS_ORDER)
  -- Returns: {action = score, ...}, {action = matches, ...}
  -- Deterministic: iterates ACTIONS_ORDER, never pairs()
end

function PredictAction(scores, ACTIONS_ORDER)
  -- Tie-breaking: First max wins (ACTIONS_ORDER priority)
  -- Returns: action string
end
```

These functions match the POC's Phase1Adapter API exactly, ensuring the validated learning algorithm works without modification. Key difference from POC: operates on ACE's full state representation (task/self/history layers).

### ace_learning.lua - Phase2Learner Integration

Ports the POC's 12-step learning algorithm directly:

```lua
function ACE:LearnFromDemonstration(decision, rules, weights, opts)
  -- decision = {
  --   demonstrated_action = "REASON",
  --   state_snapshot = {task = {...}, self = {...}, history = {...}}
  -- }
  -- opts = {
  --   learning_rate = 0.05,
  --   max_weight_delta = 0.02,
  --   min_margin = 0.05,
  --   epsilon = 0.01,
  --   salience_mode = "binary"
  -- }
  -- Returns: {
  --   updated = true,
  --   margin = 0.1,
  --   delta_total = 0.02,
  --   clamp_events = {inc = {...}, dec = {...}},
  --   comp_band_size = 1,
  --   mass_star = 0.8,
  --   demonstrated_action = "REASON"
  -- }
end
```

**12-Step Algorithm (identical to POC):**
1. Normalize state snapshot
2. Validate demonstrated action
3. Compute scores for all actions
4. Find best competitor
5. Build epsilon-band competitors
6. Find matching rules for demonstrated action
7. Handle coverage failure (no supporting rules)
8. Compute contribution mass (guard against zero)
9. Build flattened competitor list
10. Compute margin
11. Skip if sufficient margin already
12. Compute update budget
13. Increase weights for demonstrated action (contribution-based)
14. Decrease weights for competitors (symmetric update)
15. Track metrics (clamp events, salience coercions)

**Key Invariants:**
- No-competitor handling: Increase-only updates when score_comp = 0
- Epsilon-band aggregation: Flattens competitors within ε = 0.01
- Margin saturation: Bounded by max_weight_delta
- Contribution-based distribution: Updates proportional to (weight × salience)

### ace_persistence.lua - Weight Management

JSON-based persistence for learned weights:

```lua
function ACE:ExportLearnedWeights(filepath, rules, weights)
  -- Write learned weights to JSON
  -- Format: {"rule_key": learned_weight, ...}
  -- Skips rules at default weight
  -- Returns: success, error
end

function ACE:LoadWeightOverrides(filepath, rules)
  -- Load JSON, merge with rule defaults
  -- Returns: {rule_key = weight, ...} table
  -- Errors: file not found, invalid JSON, non-numeric weights
end
```

This allows inspection/editing of learned weights in a text editor, and easy version control.

### ace_training.lua - Demo Loading and Training

**Demo File Format (ACE Trace Format):**

Unlike the POC's simplified format, ACE trace files capture full execution state:

```json
{
  "demo_id": "demo_001",
  "metadata": {
    "task_difficulty": "medium",
    "teacher_confidence": 0.9,
    "tags": ["math", "calculator"]
  },
  "trace": [
    {
      "step": 0,
      "demonstrated_action": "RETRIEVE",
      "state_snapshot": {
        "task": {
          "task_type": "math",
          "complexity_estimate": 0.2,
          "input_length": 0.3,
          "entity_count": 0.0,
          "tool_requirements": ["calculator"]
        },
        "self": {
          "confidence": 0.3,
          "steps_taken": 0,
          "prev_action": null
        },
        "history": {
          "total_executions": 10,
          "success_rate": 0.8
        }
      }
    }
  ],
  "outcome": {
    "success": true,
    "termination_reason": "SUCCESS",
    "steps_taken": 3
  }
}
```

**Demo Loading API:**

```lua
function ACE:LoadDemos(directory, opts)
  -- opts = {
  --   split_ratio = 0.8,      -- train/val split
  --   shuffle = true,         -- randomize order
  --   validate = true,        -- check schema
  --   seed = 42               -- for reproducibility
  -- }
  -- Returns: {train = {...}, val = {...}}
end

function ACE:ValidateDemoStructure(demo)
  -- Checks: required fields, valid actions, state layer completeness
  -- Returns: {valid = true/false, errors = {...}}
end
```

**Training Loop:**

```lua
function ACE:TrainFromDemos(demos, rules, opts)
  -- opts = {
  --   epochs = 10,
  --   learning_rate = 0.05,
  --   max_weight_delta = 0.02,
  --   min_margin = 0.05,
  --   epsilon = 0.01,
  --   salience_mode = "binary",
  --   early_stopping_patience = 3,
  --   validation_interval = 1,
  --   seed = 42
  -- }
  -- Returns: {
  --   trained_weights,
  --   metrics_history = {
  --     {epoch = 1, train_loss = 0.5, val_loss = 0.6, clamp_events = {...}},
  --     ...
  --   },
  --   best_epoch = 7
  -- }
end
```

**Early Stopping Logic:**
- Track validation loss (sum of negative margins) after each epoch
- Stop if no improvement for `patience` epochs
- Restore weights from best epoch
- Export final weights to JSON

---

## Error Handling

### Coverage Failure Handling

When a demonstrated action has no supporting rules:

```lua
if #R_star == 0 then
  return {
    updated = false,
    uncovered = true,
    reason = "no_rules_for_demonstrated_action",
    demonstrated_action = a_star
  }
end
```

### Training Loop Error Recovery

- **Invalid demo files:** Log error, skip file, continue training
- **Coverage failures:** Accumulate in metrics, don't crash
- **Weight clamping:** Track `clamp_events` in metrics (inc/dec counts per rule)
- **Zero mass guards:** Prevent divide-by-zero with `EPS = 1e-9` checks

### Validation Errors

```lua
function ACE:ValidateDemoStructure(demo)
  local errors = {}

  -- Check required fields
  if not demo.demo_id then
    table.insert(errors, "Missing demo_id")
  end

  -- Validate demonstrated_action
  local valid_actions = {"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}
  for _, step in ipairs(demo.trace) do
    local found = false
    for _, action in ipairs(valid_actions) do
      if step.demonstrated_action == action then
        found = true
        break
      end
    end
    if not found then
      table.insert(errors, string.format("Invalid action at step %d", step.step))
    end
  end

  -- Check state_snapshot completeness
  for _, step in ipairs(demo.trace) do
    local snap = step.state_snapshot
    if not snap.task or not snap.self then
      table.insert(errors, string.format("Missing state layer at step %d", step.step))
    end
  end

  return {valid = #errors == 0, errors = errors}
end
```

### Determinism Guarantees

- All action iteration uses `ACTIONS_ORDER` (never `pairs()`)
- Demo shuffling uses seeded random if `opts.seed` provided
- No side effects in pure decision functions

---

## Testing Strategy

### Unit Tests (specs/agents/)

**ace_decision_spec.lua (20 tests):**
- NormalizeState with missing fields
- FindMatchingRules with various rule conditions
- ScoreActions with empty/empty/complex rule sets
- PredictAction tie-breaking with ACTIONS_ORDER priority

**ace_learning_spec.lua (15 tests):**
- No-competitor handling (increase-only updates)
- Epsilon-band competitor aggregation
- Margin saturation + clamping
- Coverage failure reporting
- Determinism (10 identical runs)

**ace_persistence_spec.lua (5 tests):**
- ExportLearnedWeights creates valid JSON
- LoadWeightOverrides merges with defaults
- Round-trip (export → load → verify)

**ace_training_spec.lua (8 tests):**
- LoadDemos from directory with validation
- Train/Validate split ratio
- Multi-epoch training with early stopping
- Metrics tracking (loss, clamp events, coverage failures)

### Integration Tests

- Full training pipeline: Load demos → Train → Export weights → Load weights → Verify predictions improved
- Coverage failure during training: Demo with unsupported action → Continue gracefully
- Weight clamping: Large margin updates verify bounds respected

### Performance Tests

- 100 demo files × 5 steps each × 10 epochs: Should complete in < 30 seconds
- Memory usage: Should not leak across epochs

**Total Test Count:** ~48 tests

---

## Implementation Phases

### Phase 1: Refactor Decision Functions (2 hours)

1. Create `ace_decision.lua` with pure functions
2. Extract logic from `ace.lua` (`_FindMatchingRules`, `_ScoreRules`, `_SelectAction`)
3. Make functions stateless (pass state as parameter instead of `self`)
4. Add `ACTIONS_ORDER` constant
5. Update `ace.lua` to use extracted functions
6. Write tests for `ace_decision.lua` (20 tests)

### Phase 2: Integrate Learning Algorithm (2 hours)

1. Create `ace_learning.lua`
2. Port `LearnFromDemonstration` from POC (12-step algorithm)
3. Adapt to use `ace_decision.lua` functions instead of Phase1Adapter
4. Add `opts` parameter with defaults (learning_rate, max_weight_delta, min_margin, epsilon)
5. Write tests for learning algorithm (15 tests)

### Phase 3: Weight Persistence (1 hour)

1. Create `ace_persistence.lua`
2. Implement `ExportLearnedWeights` (JSON output)
3. Implement `LoadWeightOverrides` (merge with defaults)
4. Handle file I/O errors gracefully
5. Write tests (5 tests)

### Phase 4: Demo Loading (1.5 hours)

1. Create `ace_training.lua`
2. Implement `LoadDemos` with directory scanning
3. Implement `ValidateDemoStructure` with schema checks
4. Add train/val split logic with optional shuffle
5. Support ACE trace format (task/self/history layers)
6. Write tests (5 tests)

### Phase 5: Training Loop (1.5 hours)

1. Implement `TrainFromDemos` with multi-epoch loop
2. Add early stopping logic with patience
3. Track metrics per epoch (loss, clamp events, coverage failures)
4. Restore best weights on early stopping
5. Write tests (3 tests)

### Phase 6: Integration and Documentation (1 hour)

1. Update `ace.lua` to load all new modules
2. Add convenience method: `ACE:TrainFromDemoDirectory(dir, opts)`
3. Write README for training pipeline usage
4. Create example demo files
5. Integration test: End-to-end training pipeline

**Total Estimated Time:** ~9 hours

---

## API Usage Examples

### Basic Training

```lua
local ACE = require("dslua.agents.ace")

-- Create ACE agent
local rules = require("dslua.agents.ace_rules")
local agent = ACE.new(module, {
  rules = rules,
  learning_mode = "active"
})

-- Train from demo directory
local result = agent:TrainFromDemoDirectory("demos/training", {
  epochs = 10,
  learning_rate = 0.05,
  max_weight_delta = 0.02,
  early_stopping_patience = 3,
  split_ratio = 0.8
})

print(string.format("Training complete. Best epoch: %d", result.best_epoch))

-- Learned weights exported to: demos/training/learned_weights.json
```

### Manual Weight Management

```lua
-- Export learned weights
agent:ExportLearnedWeights("weights/learned.json")

-- Load weight overrides (e.g., in production)
local overrides = agent:LoadWeightOverrides("weights/learned.json")

-- Create agent with learned weights
local production_agent = ACE.new(module, {
  rules = rules,
  learning_mode = "passive"
})
-- Apply overrides (merges with defaults)
for key, weight in pairs(overrides) do
  production_agent._weights[key] = weight
end
```

### Custom Demo Validation

```lua
-- Load demos with validation
local demos = agent:LoadDemos("demos/training", {
  validate = true,
  split_ratio = 0.8,
  shuffle = true,
  seed = 42
})

-- Check validation results
for _, demo in ipairs(demos.train) do
  if not demo.valid then
    print(string.format("Demo %s has errors:", demo.demo_id))
    for _, err in ipairs(demo.errors) do
      print(string.format("  - %s", err))
    end
  end
end
```

---

## Success Criteria

✅ All 48 unit and integration tests passing
✅ End-to-end training pipeline executes without errors
✅ Learned weights improve action prediction on validation set
✅ Demo validation catches all schema violations
✅ Early stopping prevents overfitting
✅ Weight persistence (JSON) round-trips correctly
✅ Determinism: Same seed produces identical results
✅ Performance: 500 demos × 5 steps × 10 epochs in < 30 seconds

---

## Next Steps

**Implementation:** Use `superpowers:writing-plans` to create detailed bite-sized implementation plan from this design.

**Testing:** Run full test suite after each phase to catch regressions early.

**Documentation:** Update README with training pipeline usage examples.
