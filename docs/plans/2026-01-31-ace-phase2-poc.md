# ACE Phase 2 POC: Learning Algorithm Validation

**Status:** Design Complete | Ready for Implementation

**Created:** 2026-01-31

**Goal:** Validate core Phase 2 learning mechanics (margin computation, epsilon-band competitors, bounded updates, contribution-based distribution) in isolation before full implementation.

---

## Overview

This POC tests the **learning algorithm correctness** using a minimal ACE stub that reuses Phase 1 decision primitives (rule matching, scoring) while keeping the learning loop isolated. The POC validates these critical behaviors:

1. **No-competitor handling** - Increase-only updates when demonstrated action has no competitors
2. **Epsilon-band competitor aggregation** - Correct flattening of competitor rules within epsilon
3. **Margin saturation + clamping** - Bounded updates when `learning_rate * gap` exceeds `max_weight_delta`
4. **Coverage failure** - Proper reporting when demonstrated action has no supporting rules

**Success Criteria:**
- `agreement_after > agreement_before` (learning improves decisions)
- Epsilon-band competitor aggregation is correct (no nested list bugs)
- Max delta per decision is respected (`delta_total ≤ max_weight_delta`)
- Uncovered actions tracked deterministically
- All action iteration deterministic (no `pairs()` for learning-critical loops)

---

## Architecture

**File Structure:**
```
poc/
  ace_phase2_poc.lua          -- Phase2Learner + orchestrator
  phase1_adapter.lua          -- Adapter calling Phase 1 decision primitives
  rules_poc.lua               -- 3-4 rules with mutable weights
  demos/
    poc_no_competitor_001.json
    poc_epsilon_band_001.json
    poc_margin_saturation_001.json
    poc_uncovered_001.json
  spec_phase2_poc.lua         -- Busted tests validating invariants
```

**Component Structure:**

```
┌─────────────────────────────────────────────────────────┐
│ ace_phase2_poc.lua (Phase2Learner)                      │
│ - LearnFromDecision(decision, rules, weights, opts)      │
│ - LearnFromDemonstrations(demos, rules, weights, opts)   │
│ - Orchestrates learning loop, collects metrics           │
└─────────────────────────────────────────────────────────┘
                          │
                          │ calls (pure functions)
                          ▼
┌─────────────────────────────────────────────────────────┐
│ phase1_adapter.lua (Phase1DecisionAdapter)              │
│ - NormalizeState(snapshot) → normalized_state            │
│ - ComputeSalience(rule, state, opts) → salience, diag    │
│ - FindMatchingRules(state, action, rules, weights)       │
│ - ScoreActions(state, rules, weights, ACTIONS_ORDER)     │
│                                                          │
│ Isolation Boundary:                                      │
│ - NO import of ACE:Execute, tools, history, logging     │
│ - Only imports: rule matching, normalization, salience   │
└─────────────────────────────────────────────────────────┘
```

---

## Phase1DecisionAdapter Interface

**Pure Functions (Stateless, Deterministic):**

```lua
--- Normalize state snapshot to normalized state
-- @param snapshot table Raw state_snapshot from demo
-- @return table Normalized state with task/self layers
-- @note Idempotent: if already normalized, returns unchanged
function Phase1Adapter:NormalizeState(snapshot)
```

```lua
--- Compute salience for a rule (binary mode for Phase 2)
-- @param rule table Rule with conditions
-- @param state table Normalized state
-- @param opts table Options: {salience_mode = "binary" | "threshold", salience_threshold = 0.5}
-- @return number Salience value (0.0 or 1.0 in binary mode)
-- @return table diagnostics {mode, coerced, raw}
function Phase1Adapter:ComputeSalience(rule, state, opts)
    local mode = opts.salience_mode or "binary"
    local diag = {mode = mode, coerced = false, raw = nil}

    if mode == "binary" then
        local raw = self:_RuleMatches(rule, state) and 1.0 or 0.0
        diag.raw = raw
        return raw, diag
    end

    if mode == "threshold" then
        local raw = self:_ContinuousSalience(rule, state)
        diag.raw = raw
        local threshold = opts.salience_threshold or 0.5
        local s = (raw >= threshold) and 1.0 or 0.0
        diag.coerced = (raw ~= s)
        return s, diag
    end

    error("Invalid salience_mode: " .. mode)
end
```

```lua
--- Find all rules matching an action with salience
-- @param state table Normalized state
-- @param action string Action to match
-- @param rules table Array of rules
-- @param weights table Weight lookup {rule_key -> weight}
-- @return table Array of {rule, salience, weight, salience_diag}
-- @note Returned array order matches rules array order (stable)
function Phase1Adapter:FindMatchingRules(state, action, rules, weights)
    local matches = {}
    for _, rule in ipairs(rules) do
        local salience, diag = self:ComputeSalience(rule, state, {salience_mode = "binary"})
        if salience > 0 then
            local key = rule.key or rule.id
            local w = weights[key]
            if w == nil then
                if rule.default_weight ~= nil then
                    w = rule.default_weight
                else
                    error(string.format("Missing weight for rule: %s", key))
                end
            end
            table.insert(matches, {
                rule = rule,
                salience = salience,
                weight = w,
                salience_diag = diag,
                key = key
            })
        end
    end
    return matches
end
```

```lua
--- Compute action scores deterministically
-- @param state table Normalized state
-- @param rules table Array of rules
-- @param weights table Weight lookup
-- @param ACTIONS_ORDER table Fixed iteration order
-- @return table scores[action], per_action_matches[action]
-- @note Tie-breaking: argmax uses ACTIONS_ORDER priority (first max wins)
-- @note Epsilon-band: actions with score >= best - eps, ordered by ACTIONS_ORDER
function Phase1Adapter:ScoreActions(state, rules, weights, ACTIONS_ORDER)
    local scores = {}
    local per_action_matches = {}

    for _, action in ipairs(ACTIONS_ORDER) do
        local matches = self:FindMatchingRules(state, action, rules, weights)
        per_action_matches[action] = matches

        local score = 0
        for _, pair in ipairs(matches) do
            score = score + (pair.weight * pair.salience)
        end
        scores[action] = score
    end

    return scores, per_action_matches
end
```

**Isolation Boundary (Enforced):**

The adapter **must not** import or reference:
- `ACE:Execute()` or execution loop
- Tool registry or tool execution
- History storage or persistence
- Logging subsystems

**Allowed imports only:**
- Rule condition evaluation (`_RuleMatches`, `_ConditionMatches`)
- State normalization helpers
- Salience computation primitives

---

## Phase2Learner - Learning Algorithm

**Constants:**
```lua
local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}
local EPS = 1e-9
```

**Core Learning Function:**

```lua
--- Learn from single demonstration (one decision point)
-- @param decision table {demonstrated_action, state_snapshot}
-- @param rules table Array of rules
-- @param weights table Mutable weight table {rule_key -> weight}
-- @param opts table Learning options
-- @return table metrics {updated, margin, delta_total, clamp_events, salience_coercions, comp_band_size, ...}
function Phase2Learner:LearnFromDecision(decision, rules, weights, opts)
    local a_star = decision.demonstrated_action
    local state = self.adapter:NormalizeState(decision.state_snapshot)

    -- Validate demonstrated_action
    local valid_action = false
    for _, action in ipairs(ACTIONS_ORDER) do
        if action == a_star then
            valid_action = true
            break
        end
    end
    if not valid_action then
        error(string.format("Invalid demonstrated_action: %s", a_star))
    end

    -- Step 1: Compute scores deterministically
    local scores, per_action_matches = self.adapter:ScoreActions(
        state, rules, weights, ACTIONS_ORDER
    )
    local score_star = scores[a_star]

    -- Step 2: Find best competitor (handle no competitors correctly)
    local best = nil
    for _, action in ipairs(ACTIONS_ORDER) do
        if action ~= a_star then
            local s = scores[action] or 0
            if best == nil or s > best then
                best = s
            end
        end
    end
    local score_comp = best or 0  -- 0 if no competitors

    -- Step 3: Build epsilon-band competitors (skip if best == 0)
    local comp_actions = {}
    if score_comp > 0 then  -- Only penalize if competitor has positive score
        for _, action in ipairs(ACTIONS_ORDER) do
            if action ~= a_star then
                local s = scores[action] or 0
                if s >= score_comp - (opts.epsilon or 0.01) then
                    table.insert(comp_actions, action)
                end
            end
        end
    end

    -- Special case: single-action ACTIONS_ORDER
    if #comp_actions == 0 then
        score_comp = 0
    end

    -- Step 4: Find matching rules for demonstrated action
    local R_star = self.adapter:FindMatchingRules(state, a_star, rules, weights)

    -- Step 5: Handle coverage failure
    if #R_star == 0 then
        return {
            updated = false,
            uncovered = true,
            reason = "no_rules_for_demonstrated_action",
            demonstrated_action = a_star
        }
    end

    -- Step 6: Compute contribution mass for R_star (guard against zero mass)
    local mass_star = 0
    for _, pair in ipairs(R_star) do
        mass_star = mass_star + (pair.weight * pair.salience)
    end
    if mass_star <= EPS then
        return {
            updated = false,
            uncovered = false,
            reason = "zero_mass_star",
            mass_star = mass_star
        }
    end

    -- Step 7: Build flattened R_comp from epsilon-band competitors
    local R_comp = {}
    for _, action in ipairs(comp_actions) do
        local matches = self.adapter:FindMatchingRules(state, action, rules, weights)
        for _, pair in ipairs(matches) do
            table.insert(R_comp, pair)
        end
    end

    -- Step 8: Compute margin
    local margin = score_star - score_comp

    -- Step 9: Skip if already sufficient margin
    if margin >= (opts.min_margin or 0.05) then
        return {
            updated = false,
            margin = margin,
            reason = "sufficient_margin"
        }
    end

    -- Step 10: Compute update budget
    local gap = (opts.min_margin or 0.05) - margin
    local delta_total = math.min(
        opts.max_weight_delta or 0.02,
        (opts.learning_rate or 0.05) * gap
    )

    -- Initialize metrics
    local metrics = {
        updated = true,
        margin = margin,
        gap = gap,
        delta_total = delta_total,
        score_star = score_star,
        score_comp = score_comp,
        clamp_events = {inc = {count = 0, rules = {}}, dec = {count = 0, rules = {}}},
        salience_coercions = {count = 0, rules = {}},
        comp_band_size = #comp_actions,
        mass_star = mass_star,
        demonstrated_action = a_star
    }

    -- Step 11: Increase weights for demonstrated action
    for _, pair in ipairs(R_star) do
        local key = pair.key
        local contribution = pair.weight * pair.salience
        local delta = delta_total * (contribution / mass_star)

        local old_w = weights[key]
        local new_w = math.min(1.0, math.max(0.1, old_w + delta))

        -- Track clamp events (increases)
        if new_w == 1.0 and delta > 0 then
            metrics.clamp_events.inc.count = metrics.clamp_events.inc.count + 1
            metrics.clamp_events.inc.rules[key] = (metrics.clamp_events.inc.rules[key] or 0) + 1
        end

        weights[key] = new_w
    end

    -- Step 12: Decrease weights for epsilon-band competitors (symmetric update)
    if #R_comp > 0 then
        -- Compute competitor mass
        local mass_comp = 0
        for _, pair in ipairs(R_comp) do
            mass_comp = mass_comp + (pair.weight * pair.salience)
        end

        -- Only decrease if competitors have positive mass
        if mass_comp > EPS then
            for _, pair in ipairs(R_comp) do
                local key = pair.key
                local contribution = pair.weight * pair.salience
                local delta = delta_total * (contribution / mass_comp)

                local old_w = weights[key]
                local new_w = math.min(1.0, math.max(0.1, old_w - delta))

                -- Track clamp events (decreases)
                if new_w == 0.1 and delta > 0 then
                    metrics.clamp_events.dec.count = metrics.clamp_events.dec.count + 1
                    metrics.clamp_events.dec.rules[key] = (metrics.clamp_events.dec.rules[key] or 0) + 1
                end

                weights[key] = new_w
            end
        end
    end

    -- Track salience coercions from adapter diagnostics
    for _, pair in ipairs(R_star) do
        if pair.salience_diag and pair.salience_diag.coerced then
            metrics.salience_coercions.count = metrics.salience_coercions.count + 1
            metrics.salience_coercions.rules[pair.key] = true
        end
    end

    return metrics
end
```

**Key Invariants:**
- **Determinism:** All action loops use `ipairs(ACTIONS_ORDER)`, never `pairs()`
- **Tie-breaking:** First max wins in `ACTIONS_ORDER` priority
- **Mass guards:** Check `mass_star > EPS` and `mass_comp > EPS` before distribution
- **Canonical weights:** Read/write through `weights[key]` table, never `pair.rule.weight`
- **Symmetric updates:** Increase `R_star`, decrease `R_comp` (unless `score_comp <= 0` or `mass_comp <= eps`)

---

## Demo Schema (POC Minimal)

**Demo Structure:**
```json
{
  "demo_id": "poc_no_competitor_001",
  "decisions": [
    {
      "step": 0,
      "demonstrated_action": "RETRIEVE",
      "state_snapshot": {
        "task": {
          "input_length": 0.3,
          "entity_count": 0.0,
          "task_type": "math",
          "complexity_estimate": 0.2,
          "tool_requirements": ["calculator"]
        },
        "self": {
          "confidence": 0.5,
          "steps_taken": 0,
          "prev_action": null
        }
      }
    }
  ],
  "outcome": {
    "success": true,
    "termination_reason": "SUCCESS",
    "steps_taken": 1
  }
}
```

**Schema Contract:**

**Required Fields:**
- `demo_id`: string - Unique identifier
- `decisions`: array - Decision points
- `decision.step`: integer ≥ 0, monotonic increasing
- `decision.demonstrated_action`: string - Must be in `ACTIONS_ORDER`
- `decision.state_snapshot`: object - Task + self state
- `outcome.success`: boolean
- `outcome.termination_reason`: string - "SUCCESS" | "TIMEOUT" | "ERROR"
- `outcome.steps_taken`: integer ≥ 0

**State Snapshot Fields:**

**Task Layer (all normalized to [0,1]):**
- `task.input_length`: number in [0,1]
- `task.entity_count`: number in [0,1]
- `task.task_type`: string - "math" | "factual" | "code" | "general" (unknown allowed)
- `task.complexity_estimate`: number in [0,1]
- `task.tool_requirements`: array of strings - Optional, defaults to `{}` if missing

**Self Layer:**
- `self.confidence`: number in [0,1]
- `self.steps_taken`: integer ≥ 0 (**not normalized**, passed through unchanged)
- `self.prev_action`: string or null

**Normalization Rules (POC Strict):**
- Reject if any `task.*` numeric field not in [0,1]
- Reject if `self.confidence` not in [0,1]
- Reject if `self.steps_taken` < 0
- Reject if `step` not monotonic increasing
- Reject if `demonstrated_action` not in `ACTIONS_ORDER`
- **Missing numeric fields are rejected** (POC strict mode)
- Missing `task.tool_requirements` defaults to `{}` (only allowed default)

---

## POC Rules Design

**Rules (`poc/rules_poc.lua`):**

```lua
local RULES = {
    {
        id = "math_use_calculator",
        key = "math_use_calculator",
        conditions = {
            {"task_type", "==", "math"},
            {"complexity_estimate", "<", 0.5}
        },
        action = "RETRIEVE",
        default_weight = 0.8
    },
    {
        id = "factual_reason_direct",
        key = "factual_reason_direct",
        conditions = {
            {"task_type", "==", "factual"},
            {"confidence", ">", 0.5}
        },
        action = "REASON",
        default_weight = 0.7
    },
    {
        id = "factual_use_search",
        key = "factual_use_search",
        conditions = {
            {"task_type", "==", "factual"},
            {"entity_count", ">", 0.3}
        },
        action = "RETRIEVE",
        default_weight = 0.69  -- Within epsilon of factual_reason_direct
    },
    {
        id = "general_retrieve_when_complex",
        key = "general_retrieve_when_complex",
        conditions = {
            {"task_type", "==", "general"},
            {"complexity_estimate", ">", 0.8}
        },
        action = "RETRIEVE",
        default_weight = 0.8
    },
    {
        id = "fallback_reason",
        key = "fallback_reason",
        conditions = {
            {"confidence", "<", 0.5}
        },
        action = "REASON",
        default_weight = 0.3
    }
}

return RULES
```

**Critical Rule Design Decisions:**
1. **NO unconditional fallback rule** - Prevents false positives in "no competitor" demo
2. **Epsilon-band pair** - `factual_reason_direct` (0.7) and `factual_use_search` (0.69) create scores within epsilon=0.01
3. **Margin saturation pair** - `general_retrieve_when_complex` (0.8) vs `fallback_reason` (0.3) creates large negative margin
4. **No VERIFY rules** - Guarantees "coverage failure" demo triggers correctly

---

## POC Demo Set

**Demo 1: No Competitor Case**
```json
{
  "demo_id": "poc_no_competitor_001",
  "decisions": [{
    "step": 0,
    "demonstrated_action": "RETRIEVE",
    "state_snapshot": {
      "task": {
        "task_type": "math",
        "complexity_estimate": 0.2,
        "tool_requirements": ["calculator"]
      },
      "self": {"confidence": 0.3, "steps_taken": 0, "prev_action": null}
    }
  }],
  "outcome": {"success": true, "termination_reason": "SUCCESS", "steps_taken": 1}
}
```
**Expected:** Only `math_use_calculator` matches, other actions = 0 → `score_comp = 0` → increase-only update

**Demo 2: Epsilon-Band Competitor Case**
```json
{
  "demo_id": "poc_epsilon_band_001",
  "decisions": [{
    "step": 0,
    "demonstrated_action": "REASON",
    "state_snapshot": {
      "task": {
        "task_type": "factual",
        "entity_count": 0.4,
        "complexity_estimate": 0.3
      },
      "self": {"confidence": 0.7, "steps_taken": 0, "prev_action": null}
    }
  }],
  "outcome": {"success": true, "termination_reason": "SUCCESS", "steps_taken": 1}
}
```
**Expected:** Both `factual_reason_direct` (0.7) and `factual_use_search` (0.69) match → epsilon-band includes both

**Demo 3: Margin Saturation + Clamp Case**
```json
{
  "demo_id": "poc_margin_saturation_001",
  "decisions": [{
    "step": 0,
    "demonstrated_action": "REASON",
    "state_snapshot": {
      "task": {
        "task_type": "general",
        "complexity_estimate": 0.9
      },
      "self": {"confidence": 0.1, "steps_taken": 0, "prev_action": null}
    }
  }],
  "outcome": {"success": true, "termination_reason": "SUCCESS", "steps_taken": 1}
}
```
**Expected:** `general_retrieve_when_complex` (0.8) vs `fallback_reason` (0.3) → margin = -0.5 → delta_total clamped to 0.02

**Demo 4: Coverage Failure Case**
```json
{
  "demo_id": "poc_uncovered_001",
  "decisions": [{
    "step": 0,
    "demonstrated_action": "VERIFY",
    "state_snapshot": {
      "task": {
        "task_type": "code",
        "complexity_estimate": 0.7
      },
      "self": {"confidence": 0.5, "steps_taken": 0, "prev_action": null}
    }
  }],
  "outcome": {"success": true, "termination_reason": "SUCCESS", "steps_taken": 1}
}
```
**Expected:** No rules support `VERIFY` → `updated = false`, `uncovered = true`

---

## Test Specifications (Busted)

**Test Invariants to Validate:**

```lua
describe("ACE Phase 2 POC - Learning Algorithm", function()
    it("no competitor demo produces increase-only update", function()
        -- Load demo, initialize weights
        local metrics = learner:LearnFromDecision(decision, rules, weights, opts)
        assert.is_true(metrics.updated)
        assert.is_equal(0, metrics.score_comp)
        assert.is_equal(0, metrics.clamp_events.dec.count)
        -- Weight for math_use_calculator should increase
        assert.is_true(weights["math_use_calculator"] > initial_weights["math_use_calculator"])
    end)

    it("epsilon-band demo aggregates competitors correctly", function()
        local metrics = learner:LearnFromDecision(decision, rules, weights, opts)
        assert.is_true(metrics.updated)
        assert.is_equal(2, metrics.comp_band_size)  -- Both REASON and RETRIEVE in band
        -- Both factual rules should have weight changes
        assert.is_true(weights["factual_reason_direct"] ~= initial_weights["factual_reason_direct"])
        assert.is_true(weights["factual_use_search"] ~= initial_weights["factual_use_search"])
    end)

    it("margin saturation demo clamps delta_total", function()
        local metrics = learner:LearnFromDecision(decision, rules, weights, opts)
        assert.is_true(metrics.updated)
        assert.is_true(metrics.margin < 0)  -- Negative margin
        assert.is_equal(opts.max_weight_delta, metrics.delta_total)  -- Clamped
        assert.is_true(metrics.clamp_events.inc.count > 0)  -- At least one clamp
    end)

    it("coverage failure demo reports uncovered", function()
        local metrics = learner:LearnFromDecision(decision, rules, weights, opts)
        assert.is_false(metrics.updated)
        assert.is_true(metrics.uncovered)
        assert.is_equal("VERIFY", metrics.demonstrated_action)
        -- No weights should change
        assert.is_same(weights, initial_weights)
    end)

    it("all action iteration is deterministic", function()
        -- Run learning 10 times with same inputs
        local results = {}
        for i = 1, 10 do
            local weights_copy = shallow_copy(weights)
            results[i] = learner:LearnFromDecision(decision, rules, weights_copy, opts)
        end
        -- All results should be identical
        for i = 2, 10 do
            assert.is_equal(results[1].delta_total, results[i].delta_total)
            assert.is_equal(results[1].comp_band_size, results[i].comp_band_size)
        end
    end)
end)
```

---

## Success Criteria

**After running POC:**

✅ **Learning correctness:**
- `agreement_after > agreement_before` (learning improves decisions)
- `decisions_updated` matches cases where `margin < min_margin`
- Mass guards prevent divide-by-zero (no crashes)

✅ **Determinism:**
- 10 runs with identical inputs produce identical outputs
- Epsilon-band competitor sets are stable run-to-run
- No dependence on `pairs()` iteration order

✅ **Edge cases handled:**
- No competitor → increase-only update, no decreases
- Epsilon-band → correct flattening, no nested list bugs
- Margin saturation → `delta_total` clamped to `max_weight_delta`
- Coverage failure → `uncovered = true`, no weight changes

✅ **Metrics collected:**
- Clamp events tracked separately (inc/dec)
- Salience coercions counted (if any)
- Competitor band size recorded
- Margin and delta_total computed correctly

---

## Implementation Order

**Step 1: Create adapter** (30 min)
- Implement `NormalizeState`, `ComputeSalience`, `FindMatchingRules`, `ScoreActions`
- Test with mock rules and states

**Step 2: Create learner** (1 hour)
- Implement `LearnFromDecision` with all edge cases
- Add metrics collection

**Step 3: Create rules** (15 min)
- Implement 5 rules in `rules_poc.lua`
- Verify rule matching works as expected

**Step 4: Create demos** (30 min)
- Write 4 demo JSON files
- Validate schema compliance

**Step 5: Write tests** (1 hour)
- Implement Busted tests for all 4 edge cases
- Add determinism test

**Step 6: Validate POC** (30 min)
- Run all tests, verify they pass
- Check metrics are correct
- Validate determinism (10 runs)

**Total Time Estimate:** ~4 hours

---

## Next Steps After POC

If POC succeeds:
1. Integrate `LearnFromDemonstration` into full ACE (`dslua/agents/ace.lua`)
2. Add persistence (`ExportLearnedWeights`, `LoadWeightOverrides`)
3. Implement full demo loader with validation
4. Add train/validation split logic
5. Implement multi-epoch training with early stopping

If POC fails:
1. Debug which invariant failed (determinism, mass guard, epsilon-band)
2. Fix algorithm or adjust expectations
3. Re-validate until all invariants pass

---

## Appendix: Quick Reference

**ACTIONS_ORDER (POC):**
```lua
{"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}
```

**Default Learning Options:**
```lua
{
    learning_rate = 0.05,
    max_weight_delta = 0.02,
    min_margin = 0.05,
    epsilon = 0.01,
    salience_mode = "binary"
}
```

**Weight Bounds:** [0.1, 1.0] (clamped)

**Rule Key:** `rule.key` or `rule.id` (must exist in `weights` table)

**Constants:**
```lua
EPS = 1e-9  -- Prevent divide-by-zero
```
