# ACE Phase 2: Learning from Demonstrations - Design Document

**Status:** Design v1.1 (Reviewed) | Implementation Pending

**Created:** 2026-01-30

**Last Updated:** 2026-01-30 (Addressed review feedback)

**Goal:** Enable ACE to learn from demonstration traces by updating rule weights to match expert behavior, while keeping thresholds fixed for stability.

---

## Executive Summary

Phase 2 adds **behavior cloning from demonstrations** to the ACE framework. Given curated teacher traces (with optional filtered ACE self-traces), ACE adjusts rule weights to make demonstrated actions win more decisively under the scoring model. Learning is **offline**, **weight-only**, **bounded**, and **margin-aware**.

**Key Characteristics:**
- **Signal Source:** Teacher traces (primary), filtered ACE self-traces (optional)
- **Learning Algorithm:** Gradient-free weight updates with margin-aware scaling
- **Update Targets:** Rule weights only; thresholds remain fixed
- **Demo Format:** JSON files with policy-independent state + demonstrated actions
- **Self-State:** Minimal Layer 2 fields (`confidence`, `steps_taken`, `prev_action`)
- **Training Mode:** Offline (during learn/compile step, not during task execution)

**What Phase 2 Achieves:**
- ACE can imitate expert execution paths from 20-50 demonstrations
- Rule weights adapt to demonstrated preferences via bounded updates (max 2% per decision)
- Margin-aware focusing: larger updates when demonstrations disagree with current policy
- Diagnostic tracking for threshold adjustments (prepared for Phase 3)

**What Phase 2 Does NOT Do:**
- No threshold learning (kept stable, diagnostics collected only)
- No temporal credit assignment across steps (each decision independent)
- No outcome feedback/reinforcement learning (that's Phase 3)
- No tool policy learning (kept simple)
- No online learning during execution (offline training only)

---

## Section 1: Overview

### 1.1 Learning Objective

**Primary Objective:** Minimize disagreement between ACE's selected action and the demonstrated action at each decision point (behavior cloning), using bounded weight updates.

Although demos contain sequences, Phase 2 treats each decision point independently for updates; no temporal credit assignment is performed.

### 1.2 Design Decisions Summary

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| **Signal Source** | Teacher traces (primary), filtered ACE self-traces (optional) | Clean, low-noise supervision; self-traces require strict quality filters |
| **Learning Algorithm** | Gradient-free weight updates with margin-aware scaling | Simple, interpretable, stable; bounded updates prevent drift |
| **Update Targets** | Rule weights only | Thresholds are brittle; sufficient for behavior cloning |
| **Demo Format** | JSON files | Human-readable, portable, easy to generate, versionable |
| **Self-State** | Minimal (confidence, steps_taken, prev_action) | Matches current rule conditions; avoids transient details |
| **Training Mode** | Offline (compile step) | Prevents accidental online learning; reproducible |

### 1.3 Scope Boundaries

**In Scope:**
- Load demonstrations from JSON files
- Validate demo schema and constraints
- Compute action scores using runtime model
- Update rule weights based on demonstrations
- Collect comprehensive metrics and diagnostics

**Out of Scope (Phase 3+):**
- Threshold learning (diagnostics collected, not applied)
- Temporal credit assignment across multiple steps
- Reinforcement learning from outcome feedback
- Online learning during task execution
- Tool policy learning
- Multi-hop credit assignment

### 1.4 Evaluation Protocol

**Train/Validation Split:**

To prevent overfitting and ensure generalization:

- Reserve **20% of demonstrations as holdout validation set**
- Stratify split by action type and task complexity (ensure balanced distribution)
- Report metrics on **both** training and validation sets
- Validation agreement must not degrade by more than **2 percentage points** compared to training

**Acceptance Criteria:**

```lua
{
  -- Training metrics
  train_agreement_before = 0.70,
  train_agreement_after = 0.92,
  train_improvement = 0.22,

  -- Validation metrics
  val_agreement_before = 0.68,
  val_agreement_after = 0.90,
  val_improvement = 0.22,

  -- Generalization check
  val_regression = (train_agreement_after - val_agreement_after) < 0.02  -- Must be true
}
```

**Overfitting Detection:**

- If `val_improvement < 0.5 * train_improvement`: Possible overfitting
- If `val_agreement_after < train_agreement_after - 0.02`: Generalization issue
- If `uncovered_decisions` on val set > 2× training set: Coverage gap

**Cross-Validation (Optional):**

For small demo sets (< 30 demonstrations):
- Use **5-fold cross-validation** instead of single train/val split
- Report mean ± std across folds
- Ensure each fold is stratified by action type

---

## Section 2: Demonstration Format

### 2.1 JSON Schema v1

Each demonstration is stored as a standalone JSON file:

```json
{
  "schema_version": 1,
  "demo_id": "math_calculation_001",
  "metadata": {
    "source": "teacher",
    "created_at": "2026-01-30T10:00:00Z",
    "quality_score": 1.0,
    "tags": ["math", "single-step", "calculator-needed"]
  },
  "input": {
    "question": "What is 15*27?"
  },
  "decisions": [
    {
      "step": 0,
      "state_id": "math_low_complexity#step0",
      "state_snapshot": {
        "task": {
          "input_length": 0.02,
          "entity_count": 0.1,
          "task_type": "math",
          "complexity_estimate": 0.05,
          "tool_requirements": ["calculator"]
        },
        "self": {
          "confidence": 0.5,
          "steps_taken": 0,
          "prev_action": null,
          "self_extra": {}
        }
      },
      "demonstrated_action": "RETRIEVE"
    }
  ],
  "outcome": {
    "success": true,
    "steps_taken": 1,
    "final_answer": "405",
    "termination_reason": "SUCCESS"
  }
}
```

### 2.2 Field Specifications

#### Top-Level Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schema_version` | integer | Yes | Must equal 1 for Phase 2 |
| `demo_id` | string | Yes | Unique identifier for this demonstration |
| `metadata` | object | Yes | Metadata about source and quality |
| `input` | object | Yes | Original task input (e.g., question) |
| `decisions` | array | Yes | Sequence of decision points |
| `outcome` | object | Yes | Final outcome and statistics |

#### Metadata Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `source` | string | Yes | "teacher" or "self" |
| `created_at` | string | Yes | ISO 8601 UTC timestamp |
| `quality_score` | number | No | Quality score [0,1] for filtering |
| `tags` | array | No | Free-form tags for categorization |

#### State Snapshot Fields

**Task Layer (Layer 1):**

| Field | Type | Range | Description |
|-------|------|-------|-------------|
| `input_length` | number | [0,1] | Normalized input length |
| `entity_count` | number | [0,1] | Normalized entity count |
| `task_type` | string | enum | "math", "factual", "code", "general" |
| `complexity_estimate` | number | [0,1] | Estimated complexity |
| `tool_requirements` | array | optional | Tool hints (optional, not constraints) |

**Self Layer (Layer 2 - Minimal):**

| Field | Type | Range | Description |
|-------|------|-------|-------------|
| `confidence` | number | [0,1] | Current confidence estimate |
| `steps_taken` | integer | ≥0 | Steps executed so far (NOT normalized) |
| `prev_action` | string or null | enum | Previous action (null at step 0) |
| `self_extra` | object | optional | Extension bucket for future fields |

#### Decision Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `step` | integer | Yes | Step number in sequence |
| `state_id` | string | No | Optional stable identifier for debugging/dedup |
| `state_snapshot` | object | Yes | Task and self state at this decision |
| `demonstrated_action` | string | Yes | Action chosen by expert |

#### Outcome Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `success` | boolean | Yes | True if task completed successfully |
| `steps_taken` | integer | Yes | Total steps executed (NOT normalized) |
| `final_answer` | string | No | Final answer produced |
| `termination_reason` | string | Yes | "SUCCESS", "TIMEOUT", "ERROR", "FALLBACK" |

### 2.3 Action Vocabulary

**Valid Demonstrated Actions:**
- `DECOMPOSE` - Break task into sub-tasks
- `RETRIEVE` - Retrieve information or use tools
- `REASON` - Direct reasoning with LLM
- `SYNTHESIZE` - Synthesize sub-results
- `VERIFY` - Verify or check results
- `TERMINATE` - Stop execution (included for learning when to stop)

**Excluded:**
- `ESCALATE` - Internal meta-action, not permitted in demonstrations

### 2.4 Key Design Decisions

**Policy Independence:** Demos store only states + demonstrated actions, NOT `action_scores` or `competing_actions`. Scores are computed during learning, keeping demos stable across weight updates.

**Minimal Self-State:** Only Layer 2 fields used by current rule conditions are stored. Fields like `confidence_trajectory`, `uncertainty_markers`, `tool_failures` are excluded (not used in Phase 2 rules).

**Sequential but Independent:** Demos contain sequences (multiple decision points), but Phase 2 treats each decision independently for weight updates.

**Rule Eligibility:** Only rules that activate during a decision (match the state snapshot) are eligible for weight updates. Inactive rules remain unchanged.

**Unknown Fields:** Unknown top-level and nested fields are allowed and preserved. Phase 2 learner ignores unknown fields (future-proof).

### 2.5 File Organization

```
demos/
  teacher/
    factual_001.json
    math_001.json
    complex_decomposition_001.json
  self/
    filtered_successful_2026-01.jsonl  (optional, Phase 2+)
```

**JSONL Format (Optional for Scale):**
For large demo collections, JSONL (one JSON per line) can be used for streaming:
```
{"demo_id": "math_001", ...}
{"demo_id": "factual_001", ...}
```

---

## Section 3: Demo Loader & Validator API

### 3.1 Core Functions

#### LoadDemonstration

```lua
--- Load single demonstration from JSON file
-- @param filepath string Path to demonstration JSON file
-- @return table|nil demo Validated demonstration object
-- @return table|nil err Structured error table: {code, filepath, message}
function ACE:LoadDemonstration(filepath)
```

**Error Structure:**
```lua
{
  code = "INVALID_FIELD",
  filepath = "demos/math_001.json",
  field = "decisions[1].demonstrated_action",
  message = "Invalid action: UNKNOWN_ACTION"
}
```

**Error Codes:**
- `FILE_NOT_FOUND`: File doesn't exist
- `PARSE_ERROR`: Invalid JSON syntax
- `SCHEMA_VERSION`: Missing or unsupported `schema_version`
- `MISSING_FIELD`: Required field absent
- `INVALID_FIELD`: Field value violates constraints
- `OUT_OF_BOUNDS`: Numeric value outside valid range

**Responsibilities:**
1. Parse JSON file using `dkjson`
2. Validate `schema_version` exists and equals 1 (strict mode)
3. Validate required top-level fields present
4. Validate normalization (scalars in [0,1], counts ≥ 0)
5. Validate action vocabulary
6. Return demo table or structured error

#### LoadDemonstrations

```lua
--- Load multiple demonstrations from directory
-- @param dirpath string Path to demos directory
-- @param opts table Options: {recursive: boolean, pattern: string}
-- @return table demos Array of validated demonstration objects
-- @return table errors Array of structured error tables
function ACE:LoadDemonstrations(dirpath, opts)
```

**Default Options:**
- `recursive = false` (scan top-level only)
- `pattern = "%.json$"` (Lua pattern for .json files)
- `max_file_size = 1_000_000` (1MB max per demo file, prevents JSON bombs)
- `max_decisions = 100` (max decisions per demo, prevents abuse)
- Files sorted alphabetically for **deterministic loading order**

**Safety Limits:**
- Reject files larger than `max_file_size` bytes
- Reject demos with more than `max_decisions` decision points
- Reject demos with empty `decisions` array
- These limits are configurable but have safe defaults

**Responsibilities:**
1. Scan directory for matching files (recursive if opt)
2. Check file size limits before parsing
3. Load each file using `LoadDemonstration`
4. Collect valid demos and errors separately
5. Return arrays for both success and failure cases

### 3.2 Validation Rules

#### Schema Validation

**Required Fields:**
- Top-level: `schema_version`, `demo_id`, `metadata`, `input`, `decisions`, `outcome`
- Metadata: `source`, `created_at` (ISO 8601 UTC format)
- Each decision: `step`, `state_snapshot`, `demonstrated_action`

**Schema Version Policy:**
- `schema_version` field is **required** (strict mode)
- Must equal `1` for Phase 2
- Reject demos with missing or unsupported versions

#### Normalization Validation

**Task Layer (scalars in [0,1]):**
- `task.input_length` in [0,1]
- `task.entity_count` in [0,1]
- `task.complexity_estimate` in [0,1]

**Self Layer:**
- `self.confidence` in [0,1]
- `self.steps_taken` ≥ 0 (integer count, NOT normalized)

**Outcome:**
- `outcome.steps_taken` ≥ 0 (integer count, NOT normalized)

#### Action Vocabulary Validation

- `demonstrated_action` must be in: `DECOMPOSE`, `RETRIEVE`, `REASON`, `SYNTHESIZE`, `VERIFY`, `TERMINATE`
- `self.prev_action` (if not null) must be in valid action list
- **ESCALATE** is **not permitted** in demonstrations

#### Outcome Validation

- `outcome.success` is boolean
- `outcome.termination_reason` in: `SUCCESS`, `TIMEOUT`, `ERROR`, `FALLBACK`

### 3.3 Quality Filters (for Self-Traces)

```lua
--- Check if demo meets quality threshold for learning
-- @param demo table Demonstration object
-- @return boolean passes True if demo quality criteria met
function ACE:_PassesQualityFilter(demo)
```

**Filters applied when `metadata.source == "self"`:**
- `outcome.success == true`
- `outcome.termination_reason != "FALLBACK"`
- `outcome.steps_taken < 0.8 * max_steps` (bounded execution)
- No ERROR termination reason
- `metadata.quality_score >= 0.7` (if present, optional field)
- No loop detection: no `state_id` repeated within 5 consecutive steps
- No tool failures: inferred from absence of error patterns

**Loop Detection (Self-Traces Only):**
- Track last 5 `state_id` values
- If current `state_id` appears in recent history: reject as loop
- Prevents learning from oscillation/redo patterns

**Tool Failure Inference (Self-Traces Only):**
- Reject if multiple consecutive actions show same action with low confidence
- Reject if `outcome.termination_reason == "ERROR"` or tool error indicators present

**Teacher traces** (`source == "teacher"`) bypass all quality filters (assumed curated).

---

## Section 4: Learning Algorithm

### 4.1 Learning Functions

#### LearnFromDemonstration

```lua
--- Learn from single demonstration
-- @param demo table Validated demonstration object
-- @param opts table Options: {learning_rate, max_weight_delta, min_margin}
-- @return table metrics {agreement_before, agreement_after, weight_deltas, uncovered_decisions}
function ACE:LearnFromDemonstration(demo, opts)
```

**Process:**
1. Compute agreement_before: predict action for each decision using current weights
2. For each decision point in demo:
   - Reconstruct state from `state_snapshot`
   - Run decision engine to get action scores (using runtime scoring model)
   - Identify top competitor action
   - Check if rule coverage exists for demonstrated action
   - Compute margin and apply updates if needed
3. Recompute agreement_after using updated weights
4. Return metrics

#### LearnFromDemonstrations

```lua
--- Learn from multiple demonstrations
-- @param demos table Array of demonstration objects
-- @param opts table Options: {learning_rate, max_weight_delta, min_margin}
-- @return table metrics {total_demos, total_decisions, agreement_before, agreement_after, uncovered_actions}
function ACE:LearnFromDemonstrations(demos, opts)
```

**Default Options:**
- `learning_rate = 0.05` (scales update magnitude)
- `max_weight_delta = 0.02` (max 2% weight change per decision)
- `min_margin = 0.05` (minimum desired margin between demonstrated and competitor)
- Weight bounds: `[0.1, 1.0]` (prevent rule from becoming too weak/strong)

### 4.2 Weight Update Rule

**For each decision point with demonstrated action `a*`:**

#### Step 1: Score Computation (Runtime-Aligned)

```lua
scores = {}  -- action -> score
for action in actions do
    matching_rules = FindMatchingRules(state, action)
    scores[action] = 0
    for rule, salience in matching_rules do
        scores[action] = scores[action] + (rule.weight * salience)
    end
end
```

**Note:** `FindMatchingRules` returns `{rule, salience}` pairs. Salience is computed **once per rule per decision** and reused in both scoring and update distribution.

#### Salience Contract

**Definition:** Salience quantifies how strongly a rule's conditions match the current state.

**Range and Semantics:**
- `salience ∈ [0, 1]` (normalized to unit interval)
- `salience = 1.0`: Rule fully matches (all conditions comfortably satisfied)
- `salience ≈ 0.5`: Rule partially matches (near threshold boundaries)
- `salience ≈ 0.0`: Rule barely matches (conditions at threshold edge)
- Monotonic with match quality: better match → higher salience

**Computation (Phase 2 Simplified):**
```lua
function ACE:_ComputeSalience(rule, state)
    -- Phase 2: Simple binary salience
    -- Returns 1.0 if all conditions match, 0.0 otherwise
    if self:_RuleMatches(rule, state) then
        return 1.0
    else
        return 0.0
    end
end
```

**Future Enhancement (Phase 3):**
- Distance-to-threshold salience: `1.0 - (distance / threshold_range)`
- Partial condition matching: `matched_conditions / total_conditions`
- Smooth falloff for robustness

**Rationale for [0,1] Range:**
- Keeps scores in predictable units
- Makes `min_margin` threshold interpretable (same units)
- Prevents salience scaling from varying across rule types
- Ensures learning rate is consistent across demonstrations

#### Step 2: Identify Rule Sets (with Epsilon Band)

```lua
R_star = matching_rules(state, a*)  -- Rules supporting demonstrated action
score_star = scores[a*]

-- Find top competitor with epsilon band
epsilon = 0.01  -- Score units for "near tie" threshold
a_comp = nil
score_comp = -inf
R_comp = {}  -- Will accumulate all epsilon-close competitors

for action, score in pairs(scores) do
    if action == a* then
        continue  -- Skip demonstrated action
    end

    if score > score_comp then
        -- New top competitor found, reset competitor set
        score_comp = score
        a_comp = action
        R_comp = {matching_rules(state, action)}
    elseif score >= score_comp - epsilon then
        -- Within epsilon band, include as competitor
        table.insert(R_comp, matching_rules(state, action))
    end
end
```

**Tie-Breaking Priority Order (Deterministic):**

When all scores are equal (including zero):
1. `REASON` (fallback, highest priority)
2. `RETRIEVE`
3. `DECOMPOSE`
4. `SYNTHESIZE`
5. `VERIFY`
6. `TERMINATE` (lowest priority)

This ensures deterministic behavior when scores tie and prevents random policy shifts.

**Epsilon Band Rationale:**
- Prevents oscillation when multiple competitors are near-tied
- Spreads negative updates across all epsilon-close competitors
- More stable than single-competitor updates
- Default `epsilon = 0.01` (configurable)

#### Step 3: Handle Coverage Failure

```lua
if #R_star == 0 then
    metrics.uncovered_decisions += 1
    metrics.uncovered_actions[a*] = (metrics.uncovered_actions[a*] or 0) + 1
    continue  -- skip update, can't learn without supporting rule
end
```

#### Step 4: Compute Margin and Update Budget

```lua
margin = score_star - score_comp

if margin < min_margin then
    gap = min_margin - margin
    delta_total = min(max_weight_delta, learning_rate * gap)
else
    continue  -- already sufficient margin, no update needed
end
```

**Constants:**
- `eps = 1e-9` (prevents division by zero)
- `min_margin = 0.05` (default)

#### Step 5: Distribute Updates by Contribution (Corrected)

**Critical Change:** Distribute by **contribution mass** (`weight × salience`), not salience alone. This aligns updates with the scoring model and ensures credit assignment follows actual score contributions.

```lua
-- Increase weights for demonstrated action rules
-- Distribute by contribution: (weight * salience)
C_star = sum(rule.weight * salience for rule, salience in R_star) + eps
for rule, salience in R_star do
    contribution = rule.weight * salience
    delta_i = delta_total * (contribution / C_star)
    rule.weight = clamp(rule.weight + delta_i, 0.1, 1.0)
end

-- Decrease weights for top competitor rules (with epsilon band)
if #R_comp > 0 then
    C_comp = sum(rule.weight * salience for rule, salience in R_comp) + eps
    for rule, salience in R_comp do
        contribution = rule.weight * salience
        delta_j = delta_total * (contribution / C_comp)
        rule.weight = clamp(rule.weight - delta_j, 0.1, 1.0)
    end
end
```

**Rationale for Contribution-Based Distribution:**
- A rule with `weight=0.9, salience=1.0` contributes 0.9 to score
- A rule with `weight=0.1, salience=1.0` contributes 0.1 to score
- Updates should be proportional to actual score contribution, not just salience
- Prevents over-updating low-weight rules that happen to have high salience

**Example:**
```
R_star has two rules:
  Rule A: weight=0.9, salience=1.0 → contribution=0.9 (90% of score)
  Rule B: weight=0.1, salience=1.0 → contribution=0.1 (10% of score)

If delta_total = 0.02:
  Rule A gets 0.02 * (0.9 / 1.0) = 0.018 (90% of update)
  Rule B gets 0.02 * (0.1 / 1.0) = 0.002 (10% of update)
```

**Tie-Breaking:**
- When all scores equal (including zero), ACE predicts fallback action `REASON`
- If `score_star == score_comp` and `#R_comp == 0`, only increase `R_star` weights (no decrease)

**Clamping Behavior:**
- Updates are *approximately* zero-sum
- Clamping may cause net positive drift in total weights (acceptable, weights are bounded)
- Clamp events tracked for diagnostics

#### Step 6: Optional Normalization (Prevent Drift Accumulation)

**Problem:** Clamping can cause weight drift to accumulate across many demonstrations.

**Solution:** Optional post-learning normalization to stabilize total weight mass.

```lua
--- Optional: Normalize weights to prevent drift
-- @param normalization string Type: "none" | "global_l1" | "per_action"
function ACE:_NormalizeWeights(normalization)
```

**Normalization Modes:**

1. **"none"** (default): No normalization, weights may drift slightly
2. **"global_l1"**: Global L1 normalization to keep average weight constant
   ```lua
   total_weight = sum(rule.weight for rule in all_rules)
   target_total = initial_total_weight  -- Stored at learning start
   scale = target_total / total_weight
   for rule in all_rules do
       rule.weight = clamp(rule.weight * scale, 0.1, 1.0)
   end
   ```
3. **"per_action"**: Normalize weights per-action group (keeps action "mass" comparable)
   ```lua
   for action in actions do
       action_rules = rules_supporting(action)
       total = sum(rule.weight for rule in action_rules)
       scale = action_initial_total[action] / total
       for rule in action_rules do
           rule.weight = clamp(rule.weight * scale, 0.1, 1.0)
       end
   end
   ```

**Recommendation:** Start with `"none"` (default). Enable `"global_l1"` if clamp events exceed 5% of updates.

### 4.3 Key Properties

- **Runtime-aligned:** Uses same scoring model (`weight × salience`) as execution
- **Epsilon-band competitors:** Updates spread across near-tied competitors for stability
- **Margin-aware:** Large margin → skip update (already correct). Small/negative margin → larger update.
- **Contribution-distributed:** Total delta distributed by `(weight × salience)`, aligning with score contributions
- **Bounded:** No weight change exceeds `max_weight_delta` per decision, and weights clamped to `[0.1, 1.0]`
- **Coverage-aware:** Tracks uncovered decisions where no rule supports demonstrated action
- **Deterministic tie-breaking:** Priority order prevents random shifts
- **Optional normalization:** Prevents drift accumulation across many demos
- **Update Semantics:** Even when ACE predicts the demonstrated action, updates occur if `margin < min_margin` to strengthen robustness

### 4.4 Per-Rule Tracking

```lua
rule_metrics = {
  ["complex_decomposition"] = {
    eligible_count = 15,  -- times rule matched state
    update_count = 8,     -- times rule weight was updated
    net_delta = 0.12,     -- total weight change
    avg_delta = 0.015     -- average change per update
  }
}
```

---

## Section 5: Metrics & Reporting

### 5.1 Metrics Categories

#### Dataset Identity

```lua
dataset = {
  source = "demos/teacher",
  demo_count = 10,
  decision_count = 47,
  file_hashes = {
    "math_001.json": "sha256:a1b2c3d4...",
    "factual_001.json": "sha256:e5f6g7h8..."
  },
  combined_hash = "sha256:...",  -- hash of concatenated demo_ids + file contents
  schema_version = 1,
  loaded_at = "2026-01-30T10:00:00Z",

  -- Reproducibility metadata
  ruleset = {
    version = "ace_rules.lua v1",
    hash = "sha256:...",  -- hash of rule definitions
    rule_count = 6
  },
  learner_config = {
    learning_rate = 0.05,
    max_weight_delta = 0.02,
    min_margin = 0.05,
    epsilon = 0.01,
    normalization = "none",
    weight_bounds = [0.1, 1.0]
  },
  system_info = {
    dslua_version = "0.4.0",  -- or commit hash
    learning_phase = "phase2",
    timestamp = "2026-01-30T10:00:00Z"
  }
}
```

**Metadata Rationale:**
- `ruleset.hash`: Identifies exact rule definitions used (critical for reproducibility)
- `learner_config`: Full learning hyperparameters (enables exact re-runs)
- `system_info`: Version and phase (prevents ambiguity across evolution)

#### Agreement Metrics

```lua
{
  -- Overall agreement across all demos
  total_decisions = 47,
  agreement_before = 0.72,  -- 34/47 decisions matched before learning
  agreement_after = 0.91,   -- 43/47 decisions matched after learning

  -- Per-demo breakdown
  per_demo = {
    {
      demo_id = "math_calculation_001",
      decisions = 5,
      agreement_before = 1.0,
      agreement_after = 1.0
    },
    {
      demo_id = "factual_complex_003",
      decisions = 7,
      agreement_before = 0.43,
      agreement_after = 0.86
    }
  }
}
```

**Definition:**
- `agreement_before`: Fraction of demo decisions where ACE's predicted action equals demonstrated action, computed using weights **before** any updates from this demo batch
- `agreement_after`: Fraction of demo decisions where ACE's predicted action equals demonstrated action, computed by re-running prediction on all demo decisions **after** processing the entire demo batch

#### Coverage Metrics

```lua
{
  uncovered_decisions = 2,  -- decisions where #R_star == 0
  coverage_rate = 0.96,     -- 45/47 decisions have rule coverage

  -- Breakdown by action
  uncovered_actions = {
    VERIFY = 2  -- VERIFY appeared twice but no rules matched
  },

  -- Detailed list for diagnostics
  uncovered_details = {
    {
      demo_id = "complex_synthesis_001",
      step = 3,
      demonstrated_action = "VERIFY",
      state_features = {
        task_type = "code",
        complexity_estimate = 0.73
      }
    }
  },

  -- Coverage breakdown
  coverage = {
    covered_correct = 34,      -- #R_star > 0 and prediction correct
    covered_wrong = 11,        -- #R_star > 0 but prediction wrong
    uncovered = 2,             -- #R_star == 0
    total = 47
  }
}
```

#### Update Statistics

```lua
{
  decisions_updated = 12,  -- decisions where margin < min_margin and had coverage
  update_rate = 0.26,      -- 12/47 decisions triggered updates

  -- Weight change statistics
  avg_weight_delta = 0.008,
  max_weight_delta = 0.02,
  min_weight_delta = 0.001,

  -- Update events (clarified)
  positive_update_events = 15,   -- count of weight increase operations
  negative_update_events = 12,   -- count of weight decrease operations
  total_update_events = 27,

  -- Distribution of updates
  positive_updates = 15,   -- rule weight increases
  negative_updates = 12,   -- rule weight decreases
  net_delta_sum = 0.03     -- slight positive drift (clamping effects)
}
```

**Definition:**
- `decisions_updated`: Count of demo decisions where `margin < min_margin` and `#R_star > 0`

#### Rule Utilization

```lua
{
  -- Per-rule statistics
  rules = {
    ["complex_decomposition"] = {
      eligible_count = 18,   -- matched state in 18 decisions
      update_count = 9,      -- updated in 9 decisions
      participation_rate = 0.5,  -- 9/18 eligible decisions updated
      net_delta = 0.12,
      avg_delta = 0.013,
      weight_before = 0.90,
      weight_after = 0.92
    },
    ["factual_retrieval"] = {
      eligible_count = 12,
      update_count = 7,
      participation_rate = 0.58,
      net_delta = -0.08,
      avg_delta = -0.011,
      weight_before = 0.85,
      weight_after = 0.77
    },
    ["math_calculator"] = {
      eligible_count = 8,
      update_count = 0,      -- never updated (already decisive)
      participation_rate = 0.0,
      net_delta = 0.0,
      avg_delta = 0.0,
      weight_before = 0.95,
      weight_after = 0.95
    }
  },

  -- Summary statistics
  total_rules = 6,
  active_rules = 5,         -- rules with eligible_count > 0
  dormant_rules = 1,        -- rules with eligible_count = 0
  most_updated = "complex_decomposition",
  least_updated = "math_calculator"
}
```

#### Margin Analysis

```lua
{
  -- Margin distribution before learning
  margins_before = {
    mean = 0.08,
    median = 0.06,
    min = -0.15,  -- negative = competitor won
    max = 0.42
  },

  -- Margin distribution after learning
  margins_after = {
    mean = 0.18,
    median = 0.15,
    min = 0.02,  -- all positive now
    max = 0.45
  },

  -- Margin improvement
  margin_improved = 28,     -- decisions with increased margin
  margin_degraded = 2,      -- decisions with decreased margin (other actions)
  margin_unchanged = 17     -- decisions already above min_margin
}
```

#### Per-Action Agreement

```lua
{
  actions = {
    ["REASON"] = {
      decisions = 15,
      agreement_before = 0.80,
      agreement_after = 0.93
    },
    ["RETRIEVE"] = {
      decisions = 12,
      agreement_before = 0.67,
      agreement_after = 0.92
    },
    ["DECOMPOSE"] = {
      decisions = 8,
      agreement_before = 0.75,
      agreement_after = 0.88
    },
    ["VERIFY"] = {
      decisions = 2,
      agreement_before = 0.0,  -- never predicted correctly
      agreement_after = 0.0,   -- still no coverage
      note = "uncovered_action"
    }
  }
}
```

#### Confusion Pairs

```lua
{
  ["RETRIEVE->REASON"] = 4,     -- demo: RETRIEVE, predicted: REASON
  ["DECOMPOSE->REASON"] = 2,
  ["VERIFY->SYNTHESIZE"] = 1
}

-- Summary statistics
total_confusions = 7,
most_common_confusion = "RETRIEVE->REASON",
confusion_rate = 0.15  -- 7/47 decisions
```

#### Clamp Events

```lua
clamp_events = {
  wmin_hits = 3,         -- times weight hit lower bound (0.1)
  wmax_hits = 1,         -- times weight hit upper bound (1.0)
  total_clamps = 4,
  clamp_rate = 0.04      -- 4 clamps / 100 rule updates
}
```

**Interpretation:** High `wmin_hits` may indicate missing rule coverage or overly strict `min_margin`.

#### Threshold Diagnostics (Phase 3 Preparation)

```lua
{
  threshold_candidates = [
    {
      rule = "factual_retrieval",
      field = "confidence",
      current_threshold = 0.6,
      suggested_threshold = 0.52,
      reason = "false_positive_rate = 0.18 (fires when shouldn't based on demos)",
      confidence = "medium",  -- based on 12 decisions
      evidence_count = 12
    },
    {
      rule = "complex_decomposition",
      field = "complexity_estimate",
      current_threshold = 0.6,
      suggested_threshold = 0.65,
      reason = "false_negative_rate = 0.22 (doesn't fire when it should based on demos)",
      confidence = "low",  -- based on 5 decisions
      evidence_count = 5
    }
  ]
}
```

**Diagnostic Triggers:**
- `false_positive_rate > 0.15`: Rule fires but demo chose different action
- `false_negative_rate > 0.15`: Rule doesn't fire but demo action implies it should
- `evidence_count >= 5`: Minimum decisions before suggesting threshold change

### 5.2 Reporting Functions

#### GenerateLearningReport

```lua
--- Generate human-readable learning report
-- @param metrics table Metrics from LearnFromDemonstrations
-- @return string report Formatted text report
function ACE:GenerateLearningReport(metrics)
```

**Report Format:**
```
=== ACE Learning Report ===
Dataset: demos/teacher (10 demos, 47 decisions) [sha256:...]
Schema: v1 | Loaded: 2026-01-30T10:00:00Z

Agreement:
  Before: 72% (34/47)
  After:  91% (43/47)
  Delta:  +19%

Coverage:
  Covered correct: 34
  Covered wrong:   11 (improved to 3 after learning)
  Uncovered:       2
  Top Uncovered:
    - VERIFY @ complex_synthesis_001:step3
    - DECOMPOSE @ factual_multi_002:step1

Confusions (Top 3):
  - RETRIEVE->REASON (4 cases)
  - DECOMPOSE->REASON (2 cases)
  - VERIFY->SYNTHESIZE (1 case)

Rule Updates:
  complex_decomposition: +0.12 (0.90→0.92) [9/18 updates]
  factual_retrieval:     -0.08 (0.85→0.77) [7/12 updates]
  math_calculator:       +0.00 (0.95→0.95) [0/8 updates]

Clamp Events:
  Lower bound hits: 3 | Upper bound hits: 1
  Clamp rate: 4% (suggests stable learning)

Margin:
  Mean: 0.08→0.18 (+0.10)
  Negative margins: 3→0

Threshold Candidates:
  - factual_retrieval.confidence: 0.6→0.52 (medium, 12 decisions)
```

#### ExportMetrics

```lua
--- Export metrics to JSON for external analysis
-- @param metrics table Metrics from LearnFromDemonstrations
-- @param filepath string Output file path
-- @return boolean success True if write succeeded
function ACE:ExportMetrics(metrics, filepath)
```

---

## Section 6: Implementation Notes

### 6.1 File Structure

```
dslua/agents/
  ace.lua                 (existing - Phase 1)
  ace_rules.lua           (existing - Phase 1)
  ace_learning.lua         (NEW - Phase 2)
  ace_metrics.lua         (NEW - Phase 2)

specs/agents/
  ace_spec.lua            (existing - Phase 1 tests)
  ace_learning_spec.lua   (NEW - Phase 2 tests)
  demo_fixtures.lua       (NEW - test data)

demos/
  teacher/                (NEW - demonstration files)
    math_001.json
    factual_001.json
    complex_001.json
```

### 6.2 Dependencies

**Existing Dependencies:**
- `dkjson` - JSON parsing (already in codebase)
- `dslua.core.*` - Core abstractions
- `dslua.agents.ace` - Phase 1 ACE implementation

**No New Dependencies Required**

### 6.3 Testing Strategy

**Test Categories:**

1. **Loader Tests** (`ace_learning_spec.lua`):
   - Load valid demo file
   - Reject invalid schema version
   - Reject missing required fields
   - Reject out-of-bounds values
   - Reject invalid actions
   - Apply quality filters to self-traces
   - Load multiple demos from directory
   - Handle non-existent files gracefully

2. **Learning Tests** (`ace_learning_spec.lua`):
   - Learn from single demonstration
   - Apply bounded weight updates
   - Respect margin threshold
   - Track uncovered decisions
   - Compute agreement metrics
   - Learn from multiple demonstrations
   - Distribute updates proportionally
   - Handle empty R_star (coverage failure)
   - Clamp weights to [0.1, 1.0]

3. **Metrics Tests** (`ace_metrics_spec.lua`):
   - Generate agreement metrics
   - Generate coverage metrics
   - Generate rule utilization stats
   - Compute margin distributions
   - Track confusion pairs
   - Collect threshold diagnostics
   - Generate human-readable report
   - Export metrics to JSON

4. **Integration Tests** (`ace_integration_spec.lua`):
   - End-to-end: load demos → learn → verify improvement
   - Verify agreement increases after learning
   - Verify coverage diagnostics
   - Test with real demonstration files

**Test Fixtures** (`demo_fixtures.lua`):
- Minimal valid demo
- Demo with all actions
- Demo requiring decomposition
- Demo with errors (for testing validation)
- Demo sequence for multi-step learning

### 6.4 Performance Considerations

**Scalability:**
- Expected demo count: 20-50 for Phase 2
- Expected decisions per demo: 3-10
- Total decisions: 100-500 (well within Lua performance limits)

**Optimization Opportunities (if needed):**
- Cache salience computation per rule-state pair
- Batch rule matching across decisions
- Lazy metric computation (only generate on request)

### 6.5 Future Compatibility

**Schema Versioning:**
- Phase 2 uses `schema_version = 1`
- Future phases can increment version and extend schema
- Loader rejects unknown versions by default (configurable)

**Extension Points:**
- `self_extra` bucket for additional self-monitoring fields
- Unknown fields allowed at all levels
- Threshold diagnostics collected but not applied (Phase 3)

---

## Appendix 0: Revision History

### v1.1 (2026-01-30) - Critical Review Feedback Addressed

**Overview:** Comprehensive review identified 9 key gaps/risks. All critical fixes implemented; design significantly strengthened.

#### Changes Made

**1. Salience Contract (Section 4.2 - NEW)**
- **Issue:** Salience range and semantics undefined
- **Fix:** Added explicit salience contract
  - Range: `[0, 1]` (normalized to unit interval)
  - Semantics: 1.0 = fully matched, 0.0 = barely matched
  - Monotonic with match quality
- **Impact:** Ensures scores in predictable units, makes `min_margin` interpretable

**2. Contribution-Based Distribution (Section 4.2, Step 5)**
- **Issue:** Updates distributed by salience only, not actual score contribution
- **Fix:** Changed to distribute by `weight × salience` (contribution mass)
- **Impact:** Credit assignment aligned with scoring model; prevents over-updating low-weight rules

**3. Epsilon Band for Competitors (Section 4.2, Step 2)**
- **Issue:** Single-top-competitor can oscillate in near-tie situations
- **Fix:** Added epsilon band (`ε = 0.01`) to include all near-tied competitors
- **Impact:** Prevents oscillation, more stable updates

**4. Tie-Breaking Priority Order (Section 4.2, Step 2)**
- **Issue:** Undetermined behavior when all scores equal
- **Fix:** Defined deterministic priority order: REASON > RETRIEVE > DECOMPOSE > SYNTHESIZE > VERIFY > TERMINATE
- **Impact:** Prevents random policy shifts

**5. Optional Normalization (Section 4.2, Step 6 - NEW)**
- **Issue:** Clamping causes weight drift accumulation across many demos
- **Fix:** Added optional normalization step with 3 modes: none, global_l1, per_action
- **Impact:** Prevents drift; enables stable long-term learning

**6. Train/Validation Protocol (Section 1.4 - NEW)**
- **Issue:** No evaluation protocol to prevent overfitting
- **Fix:** Added 20% holdout with stratification, acceptance criteria, overfitting detection
- **Impact:** Ensures generalization; prevents demo memorization

**7. Metrics Metadata (Section 5.1)**
- **Issue:** Metrics export not self-describing for reproducibility
- **Fix:** Added ruleset version/hash, learner config, system info to dataset identity
- **Impact:** Fully reproducible metrics; enables exact re-runs

**8. Enhanced Self-Trace Filters (Section 3.3)**
- **Issue:** Basic quality filters insufficient for robust self-trace learning
- **Fix:** Added loop detection (state_id repetition), tool failure inference, quality_score threshold
- **Impact:** Higher quality self-traces; prevents learning from pathological patterns

**9. Demo Size Limits (Section 3.1)**
- **Issue:** No protection against malformed/malicious demo files
- **Fix:** Added `max_file_size` (1MB), `max_decisions` (100), empty check
- **Impact:** Prevents JSON bombs, resource exhaustion

#### Summary Statistics

| Category | Before | After |
|----------|--------|-------|
| New sections | 0 | 2 (Salience Contract, Evaluation Protocol) |
| Critical bugs fixed | 0 | 3 (salience, distribution, epsilon) |
| Safety improvements | 0 | 3 (normalization, limits, enhanced filters) |
| Reproducibility additions | 0 | 2 (metadata, tie-breaking) |

**Validation Status:** ✅ All high-priority risks addressed; design ready for implementation

#### Unchanged (By Design)

- JSON schema structure (validated as correct)
- Action vocabulary (validated as complete)
- Core learning algorithm structure (validated as sound)
- Metrics categories (validated as comprehensive)

---

## Appendix A: Glossary

- **Behavior Cloning:** Learning to mimic demonstrated actions without understanding rewards
- **Contribution Mass:** `weight × salience` - actual score contribution of a rule to an action's total score
- **Coverage:** A rule "covers" a decision if it matches the state and supports the action
- **Epsilon Band:** Small threshold (ε = 0.01) for including near-tied competitor actions to prevent oscillation
- **Global L1 Normalization:** Weight normalization that preserves total weight mass across all rules
- **Holdout Set:** Portion of demonstrations reserved for validation (not used in training)
- **Margin:** Difference between demonstrated action score and top competitor score
- **Per-Action Normalization:** Weight normalization applied within each action group separately
- **Salience:** Degree to which a rule's conditions match the current state, normalized to [0,1]
- **Teacher Trace:** Demonstration from an expert (human or better agent)
- **Self-Trace:** Demonstration from ACE's own execution (filtered by quality)
- **Stratified Split:** Data split that maintains balanced distribution across action types
- **Uncovered Decision:** Decision where no rule supports the demonstrated action
- **Weight-Only Learning:** Updating rule weights while keeping thresholds fixed

---

## Appendix B: Example Demonstration Files

### B.1 Simple Math Task

```json
{
  "schema_version": 1,
  "demo_id": "math_calculation_001",
  "metadata": {
    "source": "teacher",
    "created_at": "2026-01-30T10:00:00Z",
    "quality_score": 1.0,
    "tags": ["math", "single-step", "calculator"]
  },
  "input": {
    "question": "What is 15*27?"
  },
  "decisions": [
    {
      "step": 0,
      "state_id": "math_simple#step0",
      "state_snapshot": {
        "task": {
          "input_length": 0.02,
          "entity_count": 0.1,
          "task_type": "math",
          "complexity_estimate": 0.05,
          "tool_requirements": ["calculator"]
        },
        "self": {
          "confidence": 0.5,
          "steps_taken": 0,
          "prev_action": null
        }
      },
      "demonstrated_action": "RETRIEVE"
    }
  ],
  "outcome": {
    "success": true,
    "steps_taken": 1,
    "final_answer": "405",
    "termination_reason": "SUCCESS"
  }
}
```

### B.2 Complex Factual Question

```json
{
  "schema_version": 1,
  "demo_id": "factual_complex_001",
  "metadata": {
    "source": "teacher",
    "created_at": "2026-01-30T10:05:00Z",
    "quality_score": 1.0,
    "tags": ["factual", "multi-step", "decomposition"]
  },
  "input": {
    "question": "What is the capital of France, and can you provide historical context about the city's founding?"
  },
  "decisions": [
    {
      "step": 0,
      "state_id": "factual_complex#step0",
      "state_snapshot": {
        "task": {
          "input_length": 0.68,
          "entity_count": 0.3,
          "task_type": "factual",
          "complexity_estimate": 0.72,
          "tool_requirements": ["search"]
        },
        "self": {
          "confidence": 0.5,
          "steps_taken": 0,
          "prev_action": null
        }
      },
      "demonstrated_action": "DECOMPOSE"
    },
    {
      "step": 1,
      "state_id": "factual_complex#step1",
      "state_snapshot": {
        "task": {
          "input_length": 0.68,
          "entity_count": 0.3,
          "task_type": "factual",
          "complexity_estimate": 0.72,
          "tool_requirements": ["search"]
        },
        "self": {
          "confidence": 0.6,
          "steps_taken": 1,
          "prev_action": "DECOMPOSE"
        }
      },
      "demonstrated_action": "RETRIEVE"
    },
    {
      "step": 2,
      "state_id": "factual_complex#step2",
      "state_snapshot": {
        "task": {
          "input_length": 0.68,
          "entity_count": 0.3,
          "task_type": "factual",
          "complexity_estimate": 0.72,
          "tool_requirements": ["search"]
        },
        "self": {
          "confidence": 0.8,
          "steps_taken": 2,
          "prev_action": "RETRIEVE"
        }
      },
      "demonstrated_action": "SYNTHESIZE"
    }
  ],
  "outcome": {
    "success": true,
    "steps_taken": 3,
    "final_answer": "Paris, founded in the 3rd century BC as a settlement on the Île de la Cité...",
    "termination_reason": "SUCCESS"
  }
}
```

---

**Document Status:** Design Complete | Ready for Implementation Plan
