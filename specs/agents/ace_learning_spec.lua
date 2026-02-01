-- specs/agents/ace_learning_spec.lua
describe("ACE Learning - LearnFromDemonstration", function()
  local LearnFromDemonstration, NormalizeState, ACTIONS_ORDER

  setup(function()
    local learning = require("dslua.agents.ace_learning")
    LearnFromDemonstration = learning.LearnFromDemonstration
    NormalizeState = require("dslua.agents.ace_decision").NormalizeState
    ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}
  end)

  it("increase-only update when no competitors", function()
    local rules = {
      {
        id = 1,
        key = "math_calculator",
        conditions = {{feature = "task_type", op = "==", value = "math"}},
        action = "RETRIEVE",
        default_weight = 0.35  -- Slightly higher than competitor
      },
      {
        id = 999,
        key = "default_reason",
        conditions = {},  -- Always matches (fallback)
        action = "REASON",
        default_weight = 0.32  -- Close enough to need update
      }
    }
    local weights = {math_calculator = 0.35, default_reason = 0.32}
    local decision = {
      demonstrated_action = "RETRIEVE",
      state_snapshot = {
        task = {task_type = "math", complexity_estimate = 0.2},
        self = {confidence = 0.3, steps_taken = 0}
      }
    }
    local opts = {
      learning_rate = 0.05,
      max_weight_delta = 0.02,
      min_margin = 0.05,  -- Margin of 0.03 is less than this
      epsilon = 0.01,
      salience_mode = "binary"
    }

    local metrics = LearnFromDemonstration(decision, rules, weights, opts, NormalizeState, ACTIONS_ORDER)

    assert.is_true(metrics.updated)
    assert.is_equal(0.32, metrics.score_comp)  -- Default fallback rule
    assert.is_true(weights.math_calculator > 0.35)  -- Increased
    assert.is_true(weights.math_calculator <= 0.35 + opts.max_weight_delta)  -- Bounded
  end)

  it("epsilon-band aggregates competitors correctly", function()
    local rules = {
      {
        id = 1,
        key = "factual_reason_direct",
        conditions = {{feature = "task_type", op = "==", value = "factual"}},
        action = "REASON",
        default_weight = 0.700
      },
      {
        id = 2,
        key = "factual_use_search",
        conditions = {{feature = "task_type", op = "==", value = "factual"}},
        action = "RETRIEVE",
        default_weight = 0.695
      }
    }
    local weights = {
      factual_reason_direct = 0.700,
      factual_use_search = 0.695
    }
    local decision = {
      demonstrated_action = "REASON",
      state_snapshot = {
        task = {task_type = "factual"},
        self = {confidence = 0.7, steps_taken = 0}
      }
    }
    local opts = {
      learning_rate = 0.05,
      max_weight_delta = 0.02,
      min_margin = 0.05,
      epsilon = 0.01,
      salience_mode = "binary"
    }

    local metrics = LearnFromDemonstration(decision, rules, weights, opts, NormalizeState, ACTIONS_ORDER)

    -- Epsilon-band should include RETRIEVE
    assert.is_equal(1, metrics.comp_band_size)

    -- Both rules should have weight changes
    assert.is_not_equal(0.700, weights.factual_reason_direct)
    assert.is_not_equal(0.695, weights.factual_use_search)
  end)

  it("margin saturation clamps delta_total", function()
    local rules = {
      {
        id = 1,
        key = "fallback_reason",
        conditions = {{feature = "task_type", op = "==", value = "general"}},
        action = "REASON",
        default_weight = 0.3
      },
      {
        id = 2,
        key = "general_retrieve",
        conditions = {{feature = "task_type", op = "==", value = "general"}},
        action = "RETRIEVE",
        default_weight = 0.8
      }
    }
    local weights = {
      fallback_reason = 0.3,
      general_retrieve = 0.8
    }
    local decision = {
      demonstrated_action = "REASON",
      state_snapshot = {
        task = {task_type = "general", complexity_estimate = 0.9},
        self = {confidence = 0.1, steps_taken = 0}
      }
    }
    local opts = {
      learning_rate = 0.05,
      max_weight_delta = 0.02,
      min_margin = 0.05,
      epsilon = 0.01,
      salience_mode = "binary"
    }

    local metrics = LearnFromDemonstration(decision, rules, weights, opts, NormalizeState, ACTIONS_ORDER)

    -- Negative margin (competitor much stronger)
    assert.is_true(metrics.margin < 0)

    -- delta_total should be clamped to max_weight_delta
    assert.is_equal(opts.max_weight_delta, metrics.delta_total)
  end)

  it("coverage failure reports uncovered", function()
    local rules = {
      {
        id = 1,
        key = "math_calculator",
        conditions = {{feature = "task_type", op = "==", value = "math"}},
        action = "RETRIEVE",
        default_weight = 0.8
      }
    }
    local weights = {math_calculator = 0.8}
    local decision = {
      demonstrated_action = "VERIFY",
      state_snapshot = {
        task = {task_type = "code", complexity_estimate = 0.7},
        self = {confidence = 0.5, steps_taken = 0}
      }
    }
    local opts = {
      learning_rate = 0.05,
      max_weight_delta = 0.02,
      min_margin = 0.05,
      epsilon = 0.01,
      salience_mode = "binary"
    }

    local metrics = LearnFromDemonstration(decision, rules, weights, opts, NormalizeState, ACTIONS_ORDER)

    assert.is_false(metrics.updated)
    assert.is_true(metrics.uncovered)
    assert.is_equal("VERIFY", metrics.demonstrated_action)
    assert.is_equal("no_rules_for_demonstrated_action", metrics.reason)
  end)

  it("sufficient margin skips update", function()
    local rules = {
      {
        id = 1,
        key = "math_calculator",
        conditions = {{feature = "task_type", op = "==", value = "math"}},
        action = "RETRIEVE",
        default_weight = 0.95
      }
    }
    local weights = {math_calculator = 0.95}
    local decision = {
      demonstrated_action = "RETRIEVE",
      state_snapshot = {
        task = {task_type = "math"},
        self = {confidence = 0.5, steps_taken = 0}
      }
    }
    local opts = {
      learning_rate = 0.05,
      max_weight_delta = 0.02,
      min_margin = 0.05,
      epsilon = 0.01,
      salience_mode = "binary"
    }

    local metrics = LearnFromDemonstration(decision, rules, weights, opts, NormalizeState, ACTIONS_ORDER)

    assert.is_false(metrics.updated)
    assert.is_equal("sufficient_margin", metrics.reason)
  end)
end)
