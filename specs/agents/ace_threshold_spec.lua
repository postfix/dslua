-- specs/agents/ace_threshold_spec.lua
-- Tests for ACE Threshold Learning Module

local Threshold = require("dslua.agents.ace_threshold")

describe("ACE Threshold Learning", function()

  describe("OptimizeThreshold", function()

    it("should find optimal threshold from decision history", function()
      local decision_history = {
        {rule_key = "test_rule", salience = 0.9, matched = true, success = true},
        {rule_key = "test_rule", salience = 0.8, matched = true, success = true},
        {rule_key = "test_rule", salience = 0.3, matched = false, success = true},
        {rule_key = "test_rule", salience = 0.7, matched = true, success = false},
        {rule_key = "test_rule", salience = 0.6, matched = true, success = false}
      }

      local result = Threshold.OptimizeThreshold("test_rule", decision_history)

      assert.is_not_nil(result)
      assert.is_not_nil(result.threshold)
      assert.is_true(result.threshold >= 0.0 and result.threshold <= 1.0)
      assert.is_not_nil(result.score)
      assert.is_equal(5, result.sample_size)
    end)

    it("should return nil for rule with no history", function()
      local decision_history = {
        {rule_key = "other_rule", salience = 0.8, matched = true, success = true}
      }

      local result, err = Threshold.OptimizeThreshold("test_rule", decision_history)

      assert.is_nil(result)
      assert.is_not_nil(err)
    end)

    it("should support different optimization methods", function()
      local decision_history = {
        {rule_key = "test_rule", salience = 0.9, matched = true, success = true},
        {rule_key = "test_rule", salience = 0.7, matched = true, success = false},
        {rule_key = "test_rule", salience = 0.3, matched = false, success = true}
      }

      local result_precision = Threshold.OptimizeThreshold("test_rule", decision_history, {method = "precision"})
      local result_recall = Threshold.OptimizeThreshold("test_rule", decision_history, {method = "recall"})
      local result_f1 = Threshold.OptimizeThreshold("test_rule", decision_history, {method = "f1"})

      assert.is_not_nil(result_precision)
      assert.is_not_nil(result_recall)
      assert.is_not_nil(result_f1)
    end)

  end)

  describe("OptimizeAllThresholds", function()

    it("should optimize thresholds for multiple rules", function()
      local rules = {
        {key = "rule1", threshold = 0.5},
        {key = "rule2", threshold = 0.6},
        {key = "rule3", threshold = 0.4}
      }

      local decision_history = {
        {rule_key = "rule1", salience = 0.8, matched = true, success = true},
        {rule_key = "rule1", salience = 0.6, matched = true, success = false},
        {rule_key = "rule2", salience = 0.9, matched = true, success = true},
        {rule_key = "rule3", salience = 0.5, matched = true, success = true}
      }

      local results = Threshold.OptimizeAllThresholds(rules, decision_history)

      assert.is_not_nil(results)
      assert.is_not_nil(results["rule1"])
      assert.is_not_nil(results["rule2"])
      assert.is_not_nil(results["rule3"])
    end)

    it("should use default threshold for rules with no history", function()
      local rules = {
        {key = "rule1", threshold = 0.5},
        {key = "rule2", threshold = 0.6}  -- No history for this one
      }

      local decision_history = {
        {rule_key = "rule1", salience = 0.8, matched = true, success = true}
      }

      local results = Threshold.OptimizeAllThresholds(rules, decision_history)

      assert.is_not_nil(results["rule1"])
      assert.is_not_nil(results["rule2"])
      assert.is_equal(0, results["rule2"].sample_size)
    end)

  end)

  describe("AdaptThreshold", function()

    it("should increase threshold when precision is below target", function()
      local current_threshold = 0.5
      local recent_outcomes = {
        {matched = true, success = false},
        {matched = true, success = false},
        {matched = true, success = true}
      }

      local new_threshold, metric = Threshold.AdaptThreshold(
        current_threshold,
        recent_outcomes,
        {
          target_metric = "precision",
          target = 0.8,
          alpha = 0.2
        }
      )

      -- Precision is 0.33, target is 0.8, so threshold should increase
      assert.is_true(new_threshold > current_threshold)
      assert.is_not_nil(metric)
    end)

    it("should decrease threshold when recall is below target", function()
      local current_threshold = 0.7
      local recent_outcomes = {
        {matched = false, success = true},
        {matched = false, success = true},
        {matched = true, success = true}
      }

      local new_threshold, metric = Threshold.AdaptThreshold(
        current_threshold,
        recent_outcomes,
        {
          target_metric = "recall",
          target = 0.8,
          alpha = 0.2
        }
      )

      -- Recall is 0.33, target is 0.8, so threshold should decrease
      assert.is_true(new_threshold < current_threshold)
      assert.is_not_nil(metric)
    end)

    it("should clamp threshold to valid range", function()
      local current_threshold = 0.5
      local recent_outcomes = {
        {matched = true, success = false}
      }

      local new_threshold, _ = Threshold.AdaptThreshold(
        current_threshold,
        recent_outcomes,
        {
          target_metric = "precision",
          target = 0.0,  -- Very low target, will try to decrease
          alpha = 1.0,  -- Large adjustment
          min_threshold = 0.2,
          max_threshold = 0.8
        }
      )

      assert.is_true(new_threshold >= 0.2 and new_threshold <= 0.8)
    end)

    it("should not change threshold when metric meets target", function()
      local current_threshold = 0.5
      local recent_outcomes = {
        {matched = true, success = true},
        {matched = true, success = true},
        {matched = true, success = true}
      }

      local new_threshold, metric = Threshold.AdaptThreshold(
        current_threshold,
        recent_outcomes,
        {
          target_metric = "precision",
          target = 0.9,  -- Slightly below perfect
          alpha = 0.1
        }
      )

      -- Precision is 1.0, which meets target, so little to no change
      assert.is_not_nil(new_threshold)
      assert.is_equal(1.0, metric)
    end)

  end)

  describe("AnalyzeThresholdSensitivity", function()

    it("should analyze threshold impact across range", function()
      local decision_history = {
        {rule_key = "test_rule", salience = 0.9, matched = true, success = true},
        {rule_key = "test_rule", salience = 0.8, matched = true, success = true},
        {rule_key = "test_rule", salience = 0.7, matched = true, success = false},
        {rule_key = "test_rule", salience = 0.6, matched = true, success = false},
        {rule_key = "test_rule", salience = 0.3, matched = false, success = true},
        {rule_key = "test_rule", salience = 0.2, matched = false, success = true}
      }

      local sensitivity = Threshold.AnalyzeThresholdSensitivity("test_rule", decision_history, {
        step = 0.2
      })

      assert.is_not_nil(sensitivity)
      assert.is_equal("test_rule", sensitivity.rule_key)
      assert.is_not_nil(sensitivity.optimal_threshold)
      assert.is_not_nil(sensitivity.robust_range)
      assert.is_not_nil(sensitivity.sensitivity_score)
      assert.is_true(#sensitivity.analysis > 0)
    end)

    it("should compute robust range for threshold", function()
      local decision_history = {
        {rule_key = "test_rule", salience = 0.9, matched = true, success = true},
        {rule_key = "test_rule", salience = 0.8, matched = true, success = true},
        {rule_key = "test_rule", salience = 0.5, matched = true, success = true}
      }

      local sensitivity = Threshold.AnalyzeThresholdSensitivity("test_rule", decision_history)

      assert.is_not_nil(sensitivity.robust_range)
      assert.is_true(sensitivity.robust_range[1] <= sensitivity.robust_range[2])
    end)

    it("should return error for rule with no history", function()
      local decision_history = {
        {rule_key = "other_rule", salience = 0.8, matched = true, success = true}
      }

      local sensitivity, err = Threshold.AnalyzeThresholdSensitivity("test_rule", decision_history)

      assert.is_nil(sensitivity)
      assert.is_not_nil(err)
    end)

  end)

  describe("RecommendThreshold", function()

    it("should recommend high threshold for conservative rules", function()
      local rule = {
        key = "test_rule",
        type = "conservative"
      }

      local threshold = Threshold.RecommendThreshold(rule)

      assert.is_true(threshold >= 0.6)
    end)

    it("should recommend low threshold for aggressive rules", function()
      local rule = {
        key = "test_rule",
        type = "aggressive"
      }

      local threshold = Threshold.RecommendThreshold(rule)

      assert.is_true(threshold <= 0.4)
    end)

    it("should recommend balanced threshold for balanced rules", function()
      local rule = {
        key = "test_rule",
        type = "balanced"
      }

      local threshold = Threshold.RecommendThreshold(rule)

      assert.is_true(threshold >= 0.4 and threshold <= 0.6)
    end)

    it("should adjust based on rule complexity", function()
      local rule_complex = {
        key = "test_rule",
        type = "balanced",
        complexity = "high"
      }

      local rule_simple = {
        key = "test_rule",
        type = "balanced",
        complexity = "low"
      }

      local threshold_complex = Threshold.RecommendThreshold(rule_complex)
      local threshold_simple = Threshold.RecommendThreshold(rule_simple)

      -- Complex rules should have higher threshold
      assert.is_true(threshold_complex > threshold_simple)
    end)

    it("should adjust based on rule importance", function()
      local rule_critical = {
        key = "test_rule",
        type = "balanced",
        importance = "critical"
      }

      local rule_optional = {
        key = "test_rule",
        type = "balanced",
        importance = "optional"
      }

      local threshold_critical = Threshold.RecommendThreshold(rule_critical)
      local threshold_optional = Threshold.RecommendThreshold(rule_optional)

      -- Critical rules should have higher threshold
      assert.is_true(threshold_critical > threshold_optional)
    end)

    it("should clamp threshold to valid range", function()
      local rule = {
        key = "test_rule",
        type = "aggressive",
        complexity = "low",
        importance = "optional"
      }

      local threshold = Threshold.RecommendThreshold(rule)

      assert.is_true(threshold >= 0.0 and threshold <= 1.0)
    end)

  end)

  describe("ComputeThresholdStats", function()

    it("should compute stats for multiple thresholds", function()
      local thresholds = {
        rule1 = 0.5,
        rule2 = 0.7,
        rule3 = 0.3
      }

      local decision_history = {
        {rule_key = "rule1", salience = 0.6, matched = true, success = true},
        {rule_key = "rule1", salience = 0.4, matched = false, success = true},
        {rule_key = "rule2", salience = 0.8, matched = true, success = true},
        {rule_key = "rule3", salience = 0.5, matched = true, success = false}
      }

      local stats = Threshold.ComputeThresholdStats(thresholds, decision_history)

      assert.is_not_nil(stats)
      assert.is_not_nil(stats["rule1"])
      assert.is_not_nil(stats["rule2"])
      assert.is_not_nil(stats["rule3"])
    end)

    it("should compute utilization metrics", function()
      local thresholds = {
        rule1 = 0.5
      }

      local decision_history = {
        {rule_key = "rule1", salience = 0.8, matched = true, success = true},
        {rule_key = "rule1", salience = 0.3, matched = false, success = true},
        {rule_key = "rule1", salience = 0.7, matched = true, success = true}
      }

      local stats = Threshold.ComputeThresholdStats(thresholds, decision_history)

      assert.is_not_nil(stats["rule1"].utilization)
      assert.is_true(stats["rule1"].utilization > 0 and stats["rule1"].utilization <= 1.0)
    end)

    it("should handle rules with no history", function()
      local thresholds = {
        rule1 = 0.5,
        rule2 = 0.6
      }

      local decision_history = {
        {rule_key = "rule1", salience = 0.8, matched = true, success = true}
      }

      local stats = Threshold.ComputeThresholdStats(thresholds, decision_history)

      assert.is_not_nil(stats["rule2"])
      assert.is_equal(0, stats["rule2"].sample_size)
      assert.is_equal(0, stats["rule2"].utilization)
    end)

  end)

  describe("Private Helper Functions", function()

    it("_evaluateThreshold should compute f1 score", function()
      local data = {
        {salience = 0.8, matched = true, success = true},
        {salience = 0.7, matched = true, success = true},
        {salience = 0.6, matched = true, success = false},
        {salience = 0.3, matched = false, success = true}
      }

      local score = Threshold._evaluateThreshold(data, 0.5, "f1")

      assert.is_not_nil(score)
      assert.is_true(score >= 0.0 and score <= 1.0)
    end)

    it("_computeMetric should calculate precision", function()
      local outcomes = {
        {matched = true, success = true},
        {matched = true, success = false},
        {matched = true, success = true}
      }

      local metric = Threshold._computeMetric(outcomes, "precision")

      -- Precision = 2/3 = 0.667
      assert.is_true(metric > 0.6 and metric < 0.7)
    end)

    it("_computeMetricsAtThreshold should return all metrics", function()
      local data = {
        {salience = 0.8, matched = true, success = true},
        {salience = 0.6, matched = true, success = false}
      }

      local metrics = Threshold._computeMetricsAtThreshold(data, 0.5)

      assert.is_not_nil(metrics.precision)
      assert.is_not_nil(metrics.recall)
      assert.is_not_nil(metrics.f1)
      assert.is_not_nil(metrics.accuracy)
      assert.is_not_nil(metrics.true_positives)
      assert.is_not_nil(metrics.false_positives)
    end)

  end)

end)
