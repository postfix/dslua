-- specs/agents/ace_online_learning_spec.lua
-- Tests for ACE Phase 3: Online Learning

local OnlineLearning = require("dslua.agents.ace_online_learning")

describe("ACE Online Learning", function()

  describe("UpdateFromOutcome", function()

    it("increases weights on successful outcome", function()
      local agent = {
        _weights = {
          rule_math_calc = 0.5,
          rule_reason = 0.6
        },
        _rules = {
          rule_math_calc = {
            id = "rule_math_calc",
            action = "USE_CALCULATOR",
            conditions = {task_type = "math"}
          },
          rule_reason = {
            id = "rule_reason",
            action = "REASON",
            conditions = {}
          }
        }
      }

      local trace = {
        steps = {
          {
            state = {task = {task_type = "math"}},
            action = "USE_CALCULATOR",
            matching_rules = {
              {rule = agent._rules.rule_math_calc, salience = 1.0}
            }
          }
        },
        final_result = {answer = "405", confidence = 0.9}
      }

      local outcome = {
        success = true,
        confidence = 0.9
      }

      local metrics = OnlineLearning.UpdateFromOutcome(agent, trace, outcome, {
        learning_rate = 0.05,
        max_weight_delta = 0.02
      })

      assert.is_true(metrics.updated)
      assert.is_true(agent._weights.rule_math_calc > 0.5) -- Weight increased
      assert.is_equal(0.6, agent._weights.rule_reason) -- Unchanged
    end)

    it("decreases weights on failed outcome", function()
      local agent = {
        _weights = {
          rule_math_calc = 0.7
        },
        _rules = {
          rule_math_calc = {
            id = "rule_math_calc",
            action = "USE_CALCULATOR",
            conditions = {task_type = "math"}
          }
        }
      }

      local trace = {
        steps = {
          {
            state = {task = {task_type = "math"}},
            action = "USE_CALCULATOR",
            matching_rules = {
              {rule = agent._rules.rule_math_calc, salience = 1.0}
            }
          }
        },
        final_result = nil,
        error = "Calculator failed"
      }

      local outcome = {
        success = false,
        confidence = 0.0
      }

      local metrics = OnlineLearning.UpdateFromOutcome(agent, trace, outcome, {
        learning_rate = 0.05,
        max_weight_delta = 0.02
      })

      assert.is_true(metrics.updated)
      assert.is_true(agent._weights.rule_math_calc < 0.7) -- Weight decreased
    end)

    it("respects max_weight_delta constraint", function()
      local agent = {
        _weights = {
          rule_calc = 0.5
        },
        _rules = {
          rule_calc = {
            id = "rule_calc",
            action = "USE_CALCULATOR",
            conditions = {}
          }
        }
      }

      local trace = {
        steps = {
          {
            state = {},
            action = "USE_CALCULATOR",
            matching_rules = {
              {rule = agent._rules.rule_calc, salience = 1.0}
            }
          }
        },
        final_result = {answer = "42", confidence = 1.0}
      }

      local outcome = {success = true, confidence = 1.0}

      -- Small delta but high learning rate
      OnlineLearning.UpdateFromOutcome(agent, trace, outcome, {
        learning_rate = 1.0,  -- Very high
        max_weight_delta = 0.01  -- But capped
      })

      -- Weight increase should be capped at max_weight_delta
      assert.is_true(agent._weights.rule_calc <= 0.51) -- 0.5 + 0.01
    end)

  end)

  describe("Experience Buffer", function()

    it("stores and retrieves experiences", function()
      local buffer = OnlineLearning.NewExperienceBuffer(3)

      buffer:push({
        trace = {steps_taken = 1},
        outcome = {success = true}
      })

      buffer:push({
        trace = {steps_taken = 2},
        outcome = {success = false}
      })

      assert.is_equal(2, buffer:Size())

      local experiences = buffer:GetAll()
      assert.is_equal(2, #experiences)
      assert.is_equal(1, experiences[1].trace.steps_taken)
      assert.is_true(experiences[1].outcome.success)
    end)

    it("evicts oldest experiences when capacity exceeded", function()
      local buffer = OnlineLearning.NewExperienceBuffer(2)

      buffer:push({id = 1})
      buffer:push({id = 2})
      buffer:push({id = 3})  -- Should evict id=1

      assert.is_equal(2, buffer:Size())

      local experiences = buffer:GetAll()
      assert.is_equal(2, #experiences)
      assert.is_equal(2, experiences[1].id)
      assert.is_equal(3, experiences[2].id)
    end)

    it("samples experiences for replay", function()
      local buffer = OnlineLearning.NewExperienceBuffer(10)

      for i = 1, 5 do
        buffer:push({id = i, value = i * 10})
      end

      local samples = buffer:Sample(3)

      assert.is_equal(3, #samples)
      -- Verify samples are from the buffer
      for _, sample in ipairs(samples) do
        assert.is_true(sample.id >= 1 and sample.id <= 5)
      end
    end)

  end)

end)
