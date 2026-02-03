-- specs/agents/ace_pattern_mining_spec.lua
-- Tests for ACE Phase 3: Pattern Mining

local PatternMining = require("dslua.agents.ace_pattern_mining")

describe("ACE Pattern Mining", function()

  describe("MinePatterns", function()

    it("discovers patterns from successful execution traces", function()
      local traces = {
        {
          features = {
            task_type = "math",
            complexity_estimate = 0.8,
            tool_requirements = {"calculator"}
          },
          action = "USE_CALCULATOR",
          outcome = {success = true, confidence = 0.9}
        },
        {
          features = {
            task_type = "math",
            complexity_estimate = 0.7,
            tool_requirements = {"calculator"}
          },
          action = "USE_CALCULATOR",
          outcome = {success = true, confidence = 0.8}
        },
        {
          features = {
            task_type = "math",
            complexity_estimate = 0.2,
            tool_requirements = {}
          },
          action = "REASON",
          outcome = {success = true, confidence = 0.7}
        }
      }

      local patterns = PatternMining.MinePatterns(traces, {
        min_success_rate = 0.8,
        min_uses = 2
      })

      -- Should discover pattern: math + high complexity + calculator → USE_CALCULATOR
      assert.is_true(#patterns > 0)

      local math_calc_pattern = nil
      for _, p in ipairs(patterns) do
        if p.state_features.task_type == "math" then
          math_calc_pattern = p
          break
        end
      end

      assert.is_not_nil(math_calc_pattern)
      assert.is_equal("USE_CALCULATOR", math_calc_pattern.recommended_action)
      assert.is_equal(2, math_calc_pattern.statistics.total_uses)
      assert.is_equal(1.0, math_calc_pattern.statistics.success_rate)
    end)

    it("filters patterns by minimum success rate", function()
      local traces = {
        {
          features = {task_type = "math", complexity_estimate = 0.8},
          action = "USE_CALCULATOR",
          outcome = {success = true, confidence = 0.9}
        },
        {
          features = {task_type = "math", complexity_estimate = 0.8},
          action = "USE_CALCULATOR",
          outcome = {success = false, confidence = 0.3}
        }
      }

      local patterns = PatternMining.MinePatterns(traces, {
        min_success_rate = 0.9,
        min_uses = 2
      })

      -- Should not discover pattern with 50% success rate
      local has_math_pattern = false
      for _, p in ipairs(patterns) do
        if p.state_features.task_type == "math" then
          has_math_pattern = true
          break
        end
      end

      assert.is_false(has_math_pattern)
    end)

    it("groups patterns by action and features", function()
      local traces = {
        {
          features = {task_type = "math", complexity_estimate = 0.8},
          action = "USE_CALCULATOR",
          outcome = {success = true}
        },
        {
          features = {task_type = "factual", complexity_estimate = 0.3},
          action = "RETRIEVE",
          outcome = {success = true}
        }
      }

      local patterns = PatternMining.MinePatterns(traces, {
        min_success_rate = 0.5,
        min_uses = 1
      })

      -- Should discover separate patterns for different actions
      assert.is_true(#patterns >= 2)
    end)

  end)

  describe("PatternToRule", function()

    it("converts pattern to ACE rule format", function()
      local pattern = {
        id = "pattern_001",
        state_features = {
          task_type = "math",
          complexity_estimate = 0.8
        },
        recommended_action = "USE_CALCULATOR",
        statistics = {
          success_count = 10,
          failure_count = 2,
          total_uses = 12,
          success_rate = 0.83
        }
      }

      local rule = PatternMining.PatternToRule(pattern)

      assert.is_not_nil(rule)
      assert.is_equal("mined_pattern_001", rule.id)
      assert.is_equal("USE_CALCULATOR", rule.action)
      assert.is_not_nil(rule.conditions)
      assert.is_equal("math", rule.conditions.task_type)
      assert.is_true(rule.weight > 0)
    end)

    it("sets initial weight based on success rate", function()
      local pattern_high_success = {
        id = "pattern_001",
        state_features = {task_type = "math"},
        recommended_action = "USE_CALCULATOR",
        statistics = {success_rate = 0.95, total_uses = 20}
      }

      local rule_high = PatternMining.PatternToRule(pattern_high_success)
      assert.is_true(rule_high.weight >= 0.8)

      local pattern_low_success = {
        id = "pattern_002",
        state_features = {task_type = "math"},
        recommended_action = "REASON",
        statistics = {success_rate = 0.6, total_uses = 10}
      }

      local rule_low = PatternMining.PatternToRule(pattern_low_success)
      assert.is_true(rule_low.weight < rule_high.weight)
    end)

  end)

  describe("ScorePattern", function()

    it("scores pattern based on success rate and coverage", function()
      local pattern = {
        state_features = {task_type = "math"},
        recommended_action = "USE_CALCULATOR",
        statistics = {
          success_count = 8,
          failure_count = 2,
          total_uses = 10,
          success_rate = 0.8
        }
      }

      local traces = {
        {features = {task_type = "math"}, action = "USE_CALCULATOR"},
        {features = {task_type = "math"}, action = "USE_CALCULATOR"}
      }

      local score = PatternMining.ScorePattern(pattern, traces)

      assert.is_not_nil(score)
      assert.is_true(score >= 0.0)
      assert.is_true(score <= 1.0)
      assert.is_true(score > 0.5) -- High success rate should give good score
    end)

    it("penalizes patterns with low coverage", function()
      local pattern_rare = {
        state_features = {
          task_type = "math",
          complexity_estimate = 1.0,  -- Very specific
          tool_requirements = {"calculator", "search"}  -- Multiple tools
        },
        recommended_action = "USE_CALCULATOR",
        statistics = {
          success_count = 1,
          failure_count = 0,
          total_uses = 1,
          success_rate = 1.0
        }
      }

      local traces = {
        {features = {task_type = "math"}},
        {features = {task_type = "factual"}}
      }

      local score = PatternMining.ScorePattern(pattern_rare, traces)

      -- Perfect success but very low coverage should still have moderate score
      assert.is_true(score < 1.0)
    end)

  end)

  describe("Private Functions", function()
    describe("_createFeatureSignature", function()
      it("should create signature with task type", function()
        local features = {task_type = "math"}

        local signature = PatternMining._createFeatureSignature(features)

        assert.is.equal("type=math", signature)
      end)

      it("should bin complexity into ranges", function()
        local low_features = {complexity_estimate = 0.3}
        local med_features = {complexity_estimate = 0.5}
        local high_features = {complexity_estimate = 0.8}

        local low_sig = PatternMining._createFeatureSignature(low_features)
        local med_sig = PatternMining._createFeatureSignature(med_features)
        local high_sig = PatternMining._createFeatureSignature(high_features)

        assert.is.truthy(low_sig:find("complexity=low"))
        assert.is.truthy(med_sig:find("complexity=medium"))
        assert.is.truthy(high_sig:find("complexity=high"))
      end)

      it("should include tool requirements", function()
        local features = {
          task_type = "factual",
          tool_requirements = {"search", "calculator"}
        }

        local signature = PatternMining._createFeatureSignature(features)

        assert.is.truthy(signature:find("type=factual"))
        assert.is.truthy(signature:find("tools=search,calculator"))
      end)

      it("should handle empty features", function()
        local features = {}

        local signature = PatternMining._createFeatureSignature(features)

        assert.is.equal("", signature)
      end)
    end)
  end)

end)
