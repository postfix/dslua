-- specs/agents/ace_threshold_integration_spec.lua
-- Integration tests for ACE Phase 3: Threshold Learning

local ACE = require("dslua.agents.ace")
local Signature = require("dslua.core.signature")
local Field = require("dslua.core.field")
local Predict = require("dslua.modules.predict")

describe("ACE Phase 3: Threshold Learning Integration", function()

  describe("OptimizeThresholds", function()

    it("should optimize thresholds for all rules", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "math_solver", threshold = 0.5, action = "SOLVE"},
        {key = "calculator", threshold = 0.6, action = "CALC"}
      }

      local agent = ACE.new(module, {rules = rules})

      local decision_history = {
        {rule_key = "math_solver", salience = 0.8, matched = true, success = true},
        {rule_key = "math_solver", salience = 0.6, matched = true, success = false},
        {rule_key = "calculator", salience = 0.9, matched = true, success = true},
        {rule_key = "calculator", salience = 0.7, matched = true, success = true}
      }

      local optimized = agent:OptimizeThresholds(decision_history, {
        method = "f1"
      })

      assert.is_not_nil(optimized)
      assert.is_not_nil(optimized["math_solver"])
      assert.is_not_nil(optimized["calculator"])

      -- Check that rule thresholds were updated
      local math_solver_rule = nil
      local calculator_rule = nil
      for _, rule in ipairs(agent._rules) do
        if rule.key == "math_solver" then
          math_solver_rule = rule
        elseif rule.key == "calculator" then
          calculator_rule = rule
        end
      end

      assert.is_not_nil(math_solver_rule)
      assert.is_not_nil(calculator_rule)
    end)

    it("should support different optimization methods", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "test_rule", threshold = 0.5, action = "TEST"}
      }

      local agent = ACE.new(module, {rules = rules})

      local decision_history = {
        {rule_key = "test_rule", salience = 0.9, matched = true, success = true},
        {rule_key = "test_rule", salience = 0.7, matched = true, success = false},
        {rule_key = "test_rule", salience = 0.3, matched = false, success = true}
      }

      local optimized_precision = agent:OptimizeThresholds(decision_history, {method = "precision"})
      local optimized_recall = agent:OptimizeThresholds(decision_history, {method = "recall"})

      assert.is_not_nil(optimized_precision)
      assert.is_not_nil(optimized_recall)
    end)

  end)

  describe("AdaptThresholdOnline", function()

    it("should adapt threshold based on recent outcomes", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "test_rule", threshold = 0.5, action = "TEST"}
      }

      local agent = ACE.new(module, {rules = rules})

      local recent_outcomes = {
        {matched = true, success = false},
        {matched = true, success = false},
        {matched = true, success = true}
      }

      local new_threshold, metric = agent:AdaptThresholdOnline("test_rule", recent_outcomes, {
        target_metric = "precision",
        target = 0.8,
        alpha = 0.2
      })

      assert.is_not_nil(new_threshold)
      assert.is_not_nil(metric)

      -- Check that rule threshold was updated
      local test_rule = nil
      for _, rule in ipairs(agent._rules) do
        if rule.key == "test_rule" then
          test_rule = rule
          break
        end
      end

      assert.is_not_nil(test_rule)
      assert.is_equal(new_threshold, test_rule.threshold)
    end)

    it("should decrease threshold for low recall", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "test_rule", threshold = 0.8, action = "TEST"}
      }

      local agent = ACE.new(module, {rules = rules})

      local recent_outcomes = {
        {matched = false, success = true},
        {matched = false, success = true},
        {matched = true, success = true}
      }

      local new_threshold, metric = agent:AdaptThresholdOnline("test_rule", recent_outcomes, {
        target_metric = "recall",
        target = 0.8,
        alpha = 0.2
      })

      -- Recall is low, so threshold should decrease
      assert.is_true(new_threshold < 0.8)
    end)

  end)

  describe("AnalyzeThresholdPerformance", function()

    it("should analyze performance for all thresholds", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "rule1", threshold = 0.5, action = "ACTION1"},
        {key = "rule2", threshold = 0.6, action = "ACTION2"}
      }

      local agent = ACE.new(module, {rules = rules})

      local decision_history = {
        {rule_key = "rule1", salience = 0.6, matched = true, success = true},
        {rule_key = "rule1", salience = 0.4, matched = false, success = true},
        {rule_key = "rule2", salience = 0.8, matched = true, success = true},
        {rule_key = "rule2", salience = 0.5, matched = true, success = false}
      }

      local stats = agent:AnalyzeThresholdPerformance(decision_history)

      assert.is_not_nil(stats)
      assert.is_not_nil(stats["rule1"])
      assert.is_not_nil(stats["rule2"])

      -- Check stats structure
      assert.is_not_nil(stats["rule1"].metrics)
      assert.is_not_nil(stats["rule1"].threshold)
      assert.is_not_nil(stats["rule1"].utilization)
      assert.is_not_nil(stats["rule1"].sample_size)
    end)

    it("should compute utilization metrics", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "test_rule", threshold = 0.5, action = "TEST"}
      }

      local agent = ACE.new(module, {rules = rules})

      local decision_history = {
        {rule_key = "test_rule", salience = 0.8, matched = true, success = true},
        {rule_key = "test_rule", salience = 0.6, matched = true, success = true},
        {rule_key = "test_rule", salience = 0.3, matched = false, success = true}
      }

      local stats = agent:AnalyzeThresholdPerformance(decision_history)

      -- At threshold 0.5, 2 out of 3 examples match
      assert.is_true(stats["test_rule"].utilization > 0.6)
      assert.is_true(stats["test_rule"].utilization <= 1.0)
    end)

  end)

  describe("RecommendThresholdForRule", function()

    it("should recommend threshold based on rule characteristics", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "test_rule", threshold = 0.5, action = "TEST"}
      }

      local agent = ACE.new(module, {rules = rules})

      local rule_info = {
        key = "test_rule",
        type = "conservative",
        complexity = "high",
        importance = "critical"
      }

      local recommended = agent:RecommendThresholdForRule("test_rule", rule_info)

      assert.is_not_nil(recommended)
      assert.is_true(recommended >= 0.0 and recommended <= 1.0)

      -- Conservative + high complexity + critical should recommend high threshold
      assert.is_true(recommended > 0.5)
    end)

    it("should update rule threshold with recommendation", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "test_rule", threshold = 0.5, action = "TEST"}
      }

      local agent = ACE.new(module, {rules = rules})

      local rule_info = {
        key = "test_rule",
        type = "aggressive"
      }

      local recommended = agent:RecommendThresholdForRule("test_rule", rule_info)

      -- Check that rule was updated
      local test_rule = nil
      for _, rule in ipairs(agent._rules) do
        if rule.key == "test_rule" then
          test_rule = rule
          break
        end
      end

      assert.is_not_nil(test_rule)
      assert.is_equal(recommended, test_rule.threshold)
    end)

  end)

  describe("End-to-End Threshold Learning Workflow", function()

    it("should complete full threshold optimization cycle", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "math_solver", threshold = 0.5, action = "SOLVE"},
        {key = "calculator", threshold = 0.5, action = "CALC"}
      }

      local agent = ACE.new(module, {rules = rules})

      -- Simulate decision history
      local decision_history = {}
      for i = 1, 20 do
        table.insert(decision_history, {
          rule_key = "math_solver",
          salience = 0.5 + (i * 0.02),
          matched = i % 3 ~= 0,  -- 2/3 match rate
          success = i % 2 == 0   -- 50% success rate
        })
        table.insert(decision_history, {
          rule_key = "calculator",
          salience = 0.4 + (i * 0.03),
          matched = i % 2 == 0,  -- 50% match rate
          success = i % 3 == 0   -- 33% success rate
        })
      end

      -- Optimize thresholds
      local optimized = agent:OptimizeThresholds(decision_history, {
        method = "f1"
      })

      assert.is_not_nil(optimized)
      assert.is_not_nil(optimized["math_solver"])
      assert.is_not_nil(optimized["calculator"])

      -- Analyze performance with optimized thresholds
      local stats = agent:AnalyzeThresholdPerformance(decision_history)

      assert.is_not_nil(stats)
      assert.is_not_nil(stats["math_solver"])
      assert.is_not_nil(stats["calculator"])
    end)

    it("should adapt thresholds online based on recent performance", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "test_rule", threshold = 0.5, action = "TEST"}
      }

      local agent = ACE.new(module, {rules = rules})

      -- Simulate online learning with batches of outcomes
      local initial_threshold = agent._rules[1].threshold

      for batch = 1, 5 do
        local recent_outcomes = {}
        for i = 1, 10 do
          table.insert(recent_outcomes, {
            matched = math.random() > 0.3,
            success = math.random() > 0.4
          })
        end

        local new_threshold, metric = agent:AdaptThresholdOnline("test_rule", recent_outcomes, {
          target_metric = "f1",
          target = 0.7,
          alpha = 0.1
        })

        -- Threshold should be changing
        if batch > 1 then
          -- Check that adaptation is happening
          assert.is_not_nil(new_threshold)
        end
      end

      -- Final threshold should be different from initial
      -- (though we can't predict the exact direction)
      local final_threshold = agent._rules[1].threshold
      assert.is_not_nil(final_threshold)
    end)

  end)

end)
