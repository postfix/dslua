-- specs/agents/ace_decision_spec.lua
describe("ACE Decision - NormalizeState", function()
  local NormalizeState

  setup(function()
    NormalizeState = require("dslua.agents.ace_decision").NormalizeState
  end)

  it("applies defaults for missing task fields", function()
    local snapshot = {
      task = {
        task_type = "math",
        -- missing: complexity_estimate, input_length, entity_count, tool_requirements
      },
      self = {
        confidence = 0.5,
        steps_taken = 0
      }
    }

    local normalized = NormalizeState(snapshot)

    assert.is_equal("math", normalized.task.task_type)
    assert.is_equal(0.5, normalized.task.complexity_estimate)  -- default
    assert.is_equal(0.0, normalized.task.input_length)  -- default
    assert.is_equal(0.0, normalized.task.entity_count)  -- default
    assert.is_same({}, normalized.task.tool_requirements)  -- default
  end)

  it("returns original state if already normalized", function()
    local snapshot = {
      task = {task_type = "factual", complexity_estimate = 0.3},
      self = {confidence = 0.7, steps_taken = 0}
    }

    local normalized = NormalizeState(snapshot)

    assert.is_equal("factual", normalized.task.task_type)
    assert.is_equal(0.3, normalized.task.complexity_estimate)
  end)
end)

describe("ACE Decision - ComputeSalience", function()
  local M

  setup(function()
    M = require("dslua.agents.ace_decision")
  end)

  it("returns 1.0 when rule matches state (binary mode)", function()
    local rule = {
      conditions = {
        {feature = "task_type", op = "==", value = "math"}
      }
    }
    local state = {
      task = {task_type = "math", complexity_estimate = 0.2},
      self = {confidence = 0.5}
    }
    local opts = {salience_mode = "binary"}

    local salience, diag = M.ComputeSalience(rule, state, opts)

    assert.is_equal(1.0, salience)
    assert.is_equal("binary", diag.mode)
    assert.is_false(diag.coerced)
  end)

  it("returns 0.0 when rule does not match state", function()
    local rule = {
      conditions = {
        {feature = "task_type", op = "==", value = "factual"}
      }
    }
    local state = {
      task = {task_type = "math", complexity_estimate = 0.2},
      self = {confidence = 0.5}
    }
    local opts = {salience_mode = "binary"}

    local salience, diag = M.ComputeSalience(rule, state, opts)

    assert.is_equal(0.0, salience)
  end)

  it("errors on invalid salience_mode", function()
    local rule = {conditions = {}}
    local state = {task = {}, self = {}}
    local opts = {salience_mode = "invalid"}

    assert.has_error(function()
      M.ComputeSalience(rule, state, opts)
    end, "Invalid salience_mode")
  end)
end)

describe("ACE Decision - FindMatchingRules", function()
  local M

  setup(function()
    M = require("dslua.agents.ace_decision")
  end)

  it("finds rules that match state and action", function()
    local rules = {
      {
        id = 1,
        key = "rule1",
        conditions = {{feature = "task_type", op = "==", value = "math"}},
        action = "RETRIEVE",
        default_weight = 0.8
      },
      {
        id = 2,
        key = "rule2",
        conditions = {{feature = "task_type", op = "==", value = "factual"}},
        action = "REASON",
        default_weight = 0.7
      }
    }
    local state = {
      task = {task_type = "math", complexity_estimate = 0.2},
      self = {confidence = 0.5}
    }
    local weights = {}
    local ACTIONS_ORDER = {"REASON", "RETRIEVE"}

    local matches = M.FindMatchingRules(state, "RETRIEVE", rules, weights, ACTIONS_ORDER)

    assert.is_equal(1, #matches)
    assert.is_equal("rule1", matches[1].key)
    assert.is_equal(0.8, matches[1].weight)
    assert.is_equal(1.0, matches[1].salience)
  end)

  it("uses explicit weight from weights table if provided", function()
    local rules = {
      {
        id = 1,
        key = "rule1",
        conditions = {{feature = "task_type", op = "==", value = "math"}},
        action = "RETRIEVE",
        default_weight = 0.8
      }
    }
    local state = {
      task = {task_type = "math"},
      self = {}
    }
    local weights = {rule1 = 0.95}  -- Override default
    local ACTIONS_ORDER = {"RETRIEVE"}

    local matches = M.FindMatchingRules(state, "RETRIEVE", rules, weights, ACTIONS_ORDER)

    assert.is_equal(1, #matches)
    assert.is_equal(0.95, matches[1].weight)
  end)

  it("returns empty table when no rules match", function()
    local rules = {
      {
        id = 1,
        key = "rule1",
        conditions = {{feature = "task_type", op = "==", value = "factual"}},
        action = "REASON",
        default_weight = 0.7
      }
    }
    local state = {
      task = {task_type = "math"},  -- Doesn't match
      self = {}
    }
    local weights = {}
    local ACTIONS_ORDER = {"REASON"}

    local matches = M.FindMatchingRules(state, "REASON", rules, weights, ACTIONS_ORDER)

    assert.is_equal(0, #matches)
  end)
end)

describe("ACE Decision - ScoreActions", function()
  local M

  setup(function()
    M = require("dslua.agents.ace_decision")
  end)

  it("computes scores for all actions deterministically", function()
    local rules = {
      {
        id = 1,
        key = "math_retrieve",
        conditions = {{feature = "task_type", op = "==", value = "math"}},
        action = "RETRIEVE",
        default_weight = 0.8
      },
      {
        id = 2,
        key = "general_reason",
        conditions = {},
        action = "REASON",
        default_weight = 0.5
      }
    }
    local state = {
      task = {task_type = "math"},
      self = {}
    }
    local weights = {}
    local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE"}

    local scores, per_action = M.ScoreActions(state, rules, weights, ACTIONS_ORDER)

    -- REASON: general_reason matches (0.5 * 1.0 = 0.5)
    assert.is_near(0.5, scores["REASON"], 0.0001)

    -- RETRIEVE: math_retrieve matches (0.8 * 1.0 = 0.8)
    assert.is_near(0.8, scores["RETRIEVE"], 0.0001)

    -- DECOMPOSE: no matches (0.0)
    assert.is_equal(0.0, scores["DECOMPOSE"])
  end)

  it("returns per-action matches for debugging", function()
    local rules = {
      {
        id = 1,
        key = "rule1",
        conditions = {{feature = "task_type", op = "==", value = "math"}},
        action = "RETRIEVE",
        default_weight = 0.8
      }
    }
    local state = {task = {task_type = "math"}, self = {}}
    local weights = {}
    local ACTIONS_ORDER = {"REASON", "RETRIEVE"}

    local scores, per_action = M.ScoreActions(state, rules, weights, ACTIONS_ORDER)

    assert.is_equal(1, #per_action["RETRIEVE"])
    assert.is_equal("rule1", per_action["RETRIEVE"][1].key)
    assert.is_equal(0, #per_action["REASON"])
  end)
end)

describe("ACE Decision - PredictAction", function()
  local M

  setup(function()
    M = require("dslua.agents.ace_decision")
  end)

  it("predicts action with highest score", function()
    local scores = {
      REASON = 0.5,
      RETRIEVE = 0.8,
      DECOMPOSE = 0.3
    }
    local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE"}

    local predicted = M.PredictAction(scores, ACTIONS_ORDER)

    assert.is_equal("RETRIEVE", predicted)
  end)

  it("ties break by ACTIONS_ORDER priority", function()
    local scores = {
      REASON = 0.8,
      RETRIEVE = 0.8,
      DECOMPOSE = 0.3
    }
    local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE"}

    local predicted = M.PredictAction(scores, ACTIONS_ORDER)

    assert.is_equal("REASON", predicted)  -- First in ACTIONS_ORDER
  end)

  it("returns first action when all scores are zero", function()
    local scores = {}
    local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE"}

    local predicted = M.PredictAction(scores, ACTIONS_ORDER)

    assert.is_equal("REASON", predicted)
  end)
end)

describe("ACE Decision - Private Functions", function()
  local M

  setup(function()
    M = require("dslua.agents.ace_decision")
  end)

  describe("_RuleMatches", function()
    it("returns true when all conditions match", function()
      local rule = {
        conditions = {
          {feature = "task_type", op = "==", value = "math"},
          {feature = "complexity_estimate", op = ">=", threshold = 0.5}
        }
      }
      local state = {
        task = {task_type = "math", complexity_estimate = 0.7},
        self = {}
      }

      local matches = M._RuleMatches(rule, state)

      assert.is_true(matches)
    end)

    it("returns false when any condition fails", function()
      local rule = {
        conditions = {
          {feature = "task_type", op = "==", value = "math"},
          {feature = "complexity_estimate", op = ">=", threshold = 0.8}
        }
      }
      local state = {
        task = {task_type = "math", complexity_estimate = 0.7},
        self = {}
      }

      local matches = M._RuleMatches(rule, state)

      assert.is_false(matches)
    end)

    it("returns true for empty conditions", function()
      local rule = {conditions = {}}
      local state = {task = {}, self = {}}

      local matches = M._RuleMatches(rule, state)

      assert.is_true(matches)
    end)
  end)

  describe("_ConditionMatches", function()
    it("matches equality condition", function()
      local condition = {feature = "task_type", op = "==", value = "math"}
      local state = {task = {task_type = "math"}, self = {}}

      local matches = M._ConditionMatches(condition, state)

      assert.is_true(matches)
    end)

    it("matches greater than condition", function()
      local condition = {feature = "complexity_estimate", op = ">", threshold = 0.5}
      local state = {task = {complexity_estimate = 0.7}, self = {}}

      local matches = M._ConditionMatches(condition, state)

      assert.is_true(matches)
    end)

    it("matches less than condition", function()
      local condition = {feature = "complexity_estimate", op = "<", threshold = 0.5}
      local state = {task = {complexity_estimate = 0.3}, self = {}}

      local matches = M._ConditionMatches(condition, state)

      assert.is_true(matches)
    end)

    it("matches greater than or equal condition", function()
      local condition = {feature = "complexity_estimate", op = ">=", threshold = 0.5}
      local state = {task = {complexity_estimate = 0.5}, self = {}}

      local matches = M._ConditionMatches(condition, state)

      assert.is_true(matches)
    end)

    it("matches less than or equal condition", function()
      local condition = {feature = "complexity_estimate", op = "<=", threshold = 0.5}
      local state = {task = {complexity_estimate = 0.5}, self = {}}

      local matches = M._ConditionMatches(condition, state)

      assert.is_true(matches)
    end)

    it("returns false for missing feature", function()
      local condition = {feature = "missing_feature", op = "==", value = "test"}
      local state = {task = {}, self = {}}

      local matches = M._ConditionMatches(condition, state)

      assert.is_false(matches)
    end)
  end)

  describe("_GetFeatureValue", function()
    it("retrieves value from task layer", function()
      local state = {task = {task_type = "math"}, self = {}}

      local value = M._GetFeatureValue(state, "task_type")

      assert.is_equal("math", value)
    end)

    it("retrieves value from self layer", function()
      local state = {task = {}, self = {confidence = 0.8}}

      local value = M._GetFeatureValue(state, "confidence")

      assert.is_equal(0.8, value)
    end)

    it("retrieves value from history layer", function()
      local state = {task = {}, self = {}, history = {prev_action = "REASON"}}

      local value = M._GetFeatureValue(state, "prev_action")

      assert.is_equal("REASON", value)
    end)

    it("returns nil for missing feature", function()
      local state = {task = {}, self = {}}

      local value = M._GetFeatureValue(state, "missing")

      assert.is_nil(value)
    end)

    it("prioritizes task over self over history", function()
      local state = {
        task = {priority = "task"},
        self = {priority = "self"},
        history = {priority = "history"}
      }

      local value = M._GetFeatureValue(state, "priority")

      assert.is_equal("task", value)
    end)
  end)
end)
