-- specs/agents/ace_temporal_credit_spec.lua
-- Tests for ACE Temporal Credit Assignment Module

local TemporalCredit = require("dslua.agents.ace_temporal_credit")

describe("ACE Temporal Credit Assignment", function()

  describe("ClassifyOutcome", function()

    it("should classify successful execution", function()
      local trace = {
        steps = {
          {decision = {rule_id = "rule1", salience = 0.8}},
          {decision = {rule_id = "rule2", salience = 0.9}}
        },
        final_result = {answer = "42"}
      }

      local outcome = TemporalCredit.ClassifyOutcome(trace)

      assert.is_true(outcome.success)
      assert.is_true(outcome.confidence > 0.5)
      assert.is_equal("Task completed successfully", outcome.reason)
    end)

    it("should classify failed execution with error", function()
      local trace = {
        steps = {
          {decision = {rule_id = "rule1", salience = 0.8}}
        },
        error = "Tool execution failed"
      }

      local outcome = TemporalCredit.ClassifyOutcome(trace)

      assert.is_false(outcome.success)
      assert.is_equal(0.0, outcome.confidence)
      assert.is_true(string.find(outcome.reason, "Tool execution failed") ~= nil)
    end)

    it("should classify failed execution without result", function()
      local trace = {
        steps = {
          {decision = {rule_id = "rule1", salience = 0.8}}
        }
        -- No final_result
      }

      local outcome = TemporalCredit.ClassifyOutcome(trace)

      assert.is_false(outcome.success)
      assert.is_true(outcome.confidence < 0.5)
    end)

    it("should use custom success criteria", function()
      local trace = {
        steps = {},
        final_result = {answer = "42"}
      }

      local custom_criteria = function(t)
        return t.final_result and t.final_result.answer == "42"
      end

      local outcome = TemporalCredit.ClassifyOutcome(trace, {
        success_criteria = custom_criteria
      })

      assert.is_true(outcome.success)
    end)

    it("should adjust confidence based on step errors", function()
      local trace_with_errors = {
        steps = {
          {decision = {rule_id = "rule1", salience = 0.8}, error = "Minor error"},
          {decision = {rule_id = "rule2", salience = 0.9}}
        },
        final_result = {answer = "42"}
      }

      local trace_clean = {
        steps = {
          {decision = {rule_id = "rule1", salience = 0.8}},
          {decision = {rule_id = "rule2", salience = 0.9}}
        },
        final_result = {answer = "42"}
      }

      local outcome_errors = TemporalCredit.ClassifyOutcome(trace_with_errors)
      local outcome_clean = TemporalCredit.ClassifyOutcome(trace_clean)

      -- Clean execution should have higher confidence
      assert.is_true(outcome_clean.confidence > outcome_errors.confidence)
    end)

  end)

  describe("AnalyzeTrace", function()

    it("should analyze simple trace", function()
      local trace = {
        steps = {
          {
            decision = {rule_id = "rule1", salience = 0.8},
            duration_ms = 100
          },
          {
            decision = {rule_id = "rule2", salience = 0.9},
            duration_ms = 200
          }
        },
        final_result = {answer = "42"}
      }

      local analysis = TemporalCredit.AnalyzeTrace(trace)

      assert.is_equal(2, analysis.step_count)
      assert.is_equal(300, analysis.total_duration_ms)
      assert.is_equal(150, analysis.avg_step_duration_ms)
      assert.is_equal(2, #analysis.decision_points)
      assert.is_equal(0, analysis.error_steps)
      assert.is_equal(2, analysis.successful_steps)
      assert.is_equal(1.0, analysis.success_ratio)
    end)

    it("should track tool usage", function()
      local trace = {
        steps = {
          {
            tool = {name = "calculator"},
            decision = {rule_id = "rule1", salience = 0.8}
          },
          {
            tool = {name = "calculator"},
            decision = {rule_id = "rule2", salience = 0.9}
          },
          {
            tool = {name = "search"},
            decision = {rule_id = "rule3", salience = 0.7}
          }
        }
      }

      local analysis = TemporalCredit.AnalyzeTrace(trace)

      assert.is_equal(2, analysis.tool_uses["calculator"])
      assert.is_equal(1, analysis.tool_uses["search"])
    end)

    it("should count error steps", function()
      local trace = {
        steps = {
          {decision = {rule_id = "rule1"}, error = "Error 1"},
          {decision = {rule_id = "rule2"}},
          {decision = {rule_id = "rule3"}, error = "Error 2"}
        }      }

      local analysis = TemporalCredit.AnalyzeTrace(trace)

      assert.is_equal(2, analysis.error_steps)
      assert.is_equal(1, analysis.successful_steps)
      assert.is_true(analysis.success_ratio < 1.0)
    end)

    it("should handle empty trace", function()
      local trace = {
        steps = {}
      }

      local analysis = TemporalCredit.AnalyzeTrace(trace)

      assert.is_equal(0, analysis.step_count)
      assert.is_equal(0, #analysis.decision_points)
      assert.is_equal(0, analysis.error_steps)
    end)

  end)

  describe("AssignCredit", function()

    it("should assign credit for successful execution", function()
      local trace = {
        steps = {
          {
            decision = {rule_id = "rule1", salience = 0.8, value = 0.5}
          },
          {
            decision = {rule_id = "rule2", salience = 0.9, value = 0.6}
          }
        },
        final_result = {answer = "42"}
      }

      local outcome = TemporalCredit.ClassifyOutcome(trace)
      local analysis = TemporalCredit.AnalyzeTrace(trace)

      local credits = TemporalCredit.AssignCredit(trace, outcome, analysis, {
        alpha = 0.1,
        gamma = 0.9,
        lambda = 0.5
      })

      assert.is_not_nil(credits)
      assert.is_not_nil(credits["rule1"])
      assert.is_not_nil(credits["rule2"])
    end)

    it("should assign negative credit for failed execution", function()
      local trace = {
        steps = {
          {
            decision = {rule_id = "rule1", salience = 0.8, value = 0.5}
          }
        },
        error = "Failed"
      }

      local outcome = TemporalCredit.ClassifyOutcome(trace)
      local analysis = TemporalCredit.AnalyzeTrace(trace)

      local credits = TemporalCredit.AssignCredit(trace, outcome, analysis, {
        alpha = 0.1,
        gamma = 0.9
      })

      -- rule1 should have negative credit
      assert.is_true(credits["rule1"].total_credit < 0)
    end)

    it("should use eligibility traces for credit assignment", function()
      local trace = {
        steps = {
          {
            decision = {rule_id = "rule1", salience = 0.8, value = 0.5}
          },
          {
            decision = {rule_id = "rule2", salience = 0.9, value = 0.6}
          },
          {
            decision = {rule_id = "rule1", salience = 0.7, value = 0.4}
          }
        },
        final_result = {answer = "42"}
      }

      local outcome = TemporalCredit.ClassifyOutcome(trace)
      local analysis = TemporalCredit.AnalyzeTrace(trace)

      local credits = TemporalCredit.AssignCredit(trace, outcome, analysis, {
        alpha = 0.1,
        gamma = 0.9,
        lambda = 0.5
      })

      -- rule1 should have accumulated credit from both occurrences
      assert.is_not_nil(credits["rule1"])
      assert.is_equal(2, #credits["rule1"].contributions)
    end)

  end)

  describe("DistributeCreditBySalience", function()

    it("should distribute credit proportionally to salience", function()
      local trace = {
        steps = {
          {
            decision = {rule_id = "rule1", salience = 0.8}
          },
          {
            decision = {rule_id = "rule2", salience = 0.2}
          }
        },
        final_result = {answer = "42"}
      }

      local outcome = TemporalCredit.ClassifyOutcome(trace)
      local analysis = TemporalCredit.AnalyzeTrace(trace)

      local credits = TemporalCredit.DistributeCreditBySalience(trace, outcome, analysis)

      -- rule1 should get 80% of credit, rule2 should get 20%
      local rule1_credit = credits["rule1"].total_credit
      local rule2_credit = credits["rule2"].total_credit

      -- rule1 should have 4x the credit of rule2
      local ratio = rule1_credit / rule2_credit
      assert.is_true(ratio > 3.5 and ratio < 4.5)
    end)

    it("should handle zero salience", function()
      local trace = {
        steps = {
          {
            decision = {rule_id = "rule1", salience = 0.0}
          },
          {
            decision = {rule_id = "rule2", salience = 1.0}
          }
        },
        final_result = {answer = "42"}
      }

      local outcome = TemporalCredit.ClassifyOutcome(trace)
      local analysis = TemporalCredit.AnalyzeTrace(trace)

      local credits = TemporalCredit.DistributeCreditBySalience(trace, outcome, analysis)

      -- rule2 should get all credit
      assert.is_equal(0, credits["rule1"].total_credit)
      assert.is_true(credits["rule2"].total_credit > 0)
    end)

  end)

  describe("AssignCreditByRecency", function()

    it("should weight recent steps more heavily", function()
      local trace = {
        steps = {
          {
            decision = {rule_id = "rule1", salience = 0.8}
          },
          {
            decision = {rule_id = "rule2", salience = 0.8}
          }
        },
        final_result = {answer = "42"}
      }

      local outcome = TemporalCredit.ClassifyOutcome(trace)
      local analysis = TemporalCredit.AnalyzeTrace(trace)

      local credits = TemporalCredit.AssignCreditByRecency(trace, outcome, analysis, {
        decay = 0.5
      })

      -- rule2 (more recent) should have higher credit than rule1
      local rule1_credit = credits["rule1"].total_credit
      local rule2_credit = credits["rule2"].total_credit

      assert.is_true(rule2_credit > rule1_credit)
    end)

    it("should apply decay factor correctly", function()
      local trace = {
        steps = {
          {decision = {rule_id = "rule1", salience = 0.8}},
          {decision = {rule_id = "rule2", salience = 0.8}},
          {decision = {rule_id = "rule3", salience = 0.8}}
        },
        final_result = {answer = "42"}
      }

      local outcome = TemporalCredit.ClassifyOutcome(trace)
      local analysis = TemporalCredit.AnalyzeTrace(trace)

      local decay = 0.5
      local credits = TemporalCredit.AssignCreditByRecency(trace, outcome, analysis, {
        decay = decay
      })

      -- With decay=0.5 and 3 steps:
      -- rule3: decay^0 = 1.0
      -- rule2: decay^1 = 0.5
      -- rule1: decay^2 = 0.25
      local c1 = credits["rule1"].total_credit
      local c2 = credits["rule2"].total_credit
      local c3 = credits["rule3"].total_credit

      assert.is_true(c3 > c2)
      assert.is_true(c2 > c1)
    end)

  end)

  describe("ComputeTemporalDifferences", function()

    it("should compute TD errors for each step", function()
      local trace = {
        steps = {
          {decision = {rule_id = "rule1", value = 0.3}},
          {decision = {rule_id = "rule2", value = 0.5}},
          {decision = {rule_id = "rule3", value = 0.7}}
        },
        final_result = {answer = "42"}
      }

      local outcome = TemporalCredit.ClassifyOutcome(trace)

      local tds = TemporalCredit.ComputeTemporalDifferences(trace, outcome, {
        gamma = 0.9
      })

      assert.is_equal(3, #tds)
      assert.is_not_nil(tds[1].td_error)
      assert.is_not_nil(tds[2].td_error)
      assert.is_not_nil(tds[3].td_error)
    end)

    it("should calculate correct TD values", function()
      local trace = {
        steps = {
          {decision = {rule_id = "rule1", value = 0.0}},
          {decision = {rule_id = "rule2", value = 0.0}}
        },
        final_result = {answer = "42"}
      }

      local outcome = TemporalCredit.ClassifyOutcome(trace)
      local reward = outcome.confidence  -- Should be ~1.0

      local tds = TemporalCredit.ComputeTemporalDifferences(trace, outcome, {
        gamma = 0.9
      })

      -- Last step: TD = reward + gamma * 0 - 0 = reward
      assert.is_true(math.abs(tds[2].td_error - reward) < 0.01)
    end)

  end)

  describe("AggregateCredits", function()

    it("should aggregate credits from multiple traces", function()
      local credits1 = {
        rule1 = {rule_id = "rule1", total_credit = 0.5, contributions = {}},
        rule2 = {rule_id = "rule2", total_credit = 0.3, contributions = {}}
      }

      local credits2 = {
        rule1 = {rule_id = "rule1", total_credit = 0.4, contributions = {}},
        rule3 = {rule_id = "rule3", total_credit = 0.2, contributions = {}}
      }

      local aggregated = TemporalCredit.AggregateCredits({credits1, credits2})

      assert.is_equal(0.9, aggregated["rule1"].total_credit)
      assert.is_equal(0.3, aggregated["rule2"].total_credit)
      assert.is_equal(0.2, aggregated["rule3"].total_credit)
    end)

    it("should count contributions", function()
      local credits1 = {
        rule1 = {rule_id = "rule1", total_credit = 0.5, contribution_count = 2, contributions = {}}
      }

      local credits2 = {
        rule1 = {rule_id = "rule1", total_credit = 0.4, contribution_count = 3, contributions = {}}
      }

      local aggregated = TemporalCredit.AggregateCredits({credits1, credits2})

      assert.is_equal(5, aggregated["rule1"].contribution_count)
    end)

  end)

  describe("NormalizeCredits", function()

    it("should normalize credits to [0, 1]", function()
      local credits = {
        rule1 = {rule_id = "rule1", total_credit = -1.0, contribution_count = 1},
        rule2 = {rule_id = "rule2", total_credit = 0.0, contribution_count = 1},
        rule3 = {rule_id = "rule3", total_credit = 1.0, contribution_count = 1}
      }

      local normalized = TemporalCredit.NormalizeCredits(credits)

      assert.is_equal(0.0, normalized["rule1"].normalized_credit)
      assert.is_equal(0.5, normalized["rule2"].normalized_credit)
      assert.is_equal(1.0, normalized["rule3"].normalized_credit)
    end)

    it("should handle identical credits", function()
      local credits = {
        rule1 = {rule_id = "rule1", total_credit = 0.5, contribution_count = 1},
        rule2 = {rule_id = "rule2", total_credit = 0.5, contribution_count = 1}
      }

      local normalized = TemporalCredit.NormalizeCredits(credits)

      -- Both should be 0.5 when identical
      assert.is_equal(0.5, normalized["rule1"].normalized_credit)
      assert.is_equal(0.5, normalized["rule2"].normalized_credit)
    end)

    it("should preserve original credits", function()
      local credits = {
        rule1 = {rule_id = "rule1", total_credit = 0.7, contribution_count = 1}
      }

      local normalized = TemporalCredit.NormalizeCredits(credits)

      assert.is_equal(0.7, normalized["rule1"].total_credit)
    end)

  end)

end)
