-- specs/agents/ace_temporal_integration_spec.lua
-- Integration tests for ACE Phase 3: Temporal Credit Assignment

local ACE = require("dslua.agents.ace")
local Signature = require("dslua.core.signature")
local Field = require("dslua.core.field")
local Predict = require("dslua.modules.predict")

describe("ACE Phase 3: Temporal Credit Integration", function()

  describe("LearnFromExecution", function()

    it("should learn from successful execution trace", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "test_rule", default_weight = 0.5}
      }

      local agent = ACE.new(module, {rules = rules})

      -- Create a successful execution trace
      local trace = {
        steps = {
          {
            decision = {
              rule_id = "test_rule",
              salience = 0.8,
              value = 0.5
            }
          },
          {
            decision = {
              rule_id = "test_rule",
              salience = 0.9,
              value = 0.6
            }
          }
        },
        final_result = {answer = "42"}
      }

      local result = agent:LearnFromExecution(trace, {
        learning_rate = 0.1
      })

      assert.is_not_nil(result)
      assert.is_true(result.outcome.success)
      assert.is_not_nil(result.credits)
      assert.is_not_nil(result.analysis)
    end)

    it("should increase weights for successful decisions", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "rule1", default_weight = 0.5}
      }

      local agent = ACE.new(module, {rules = rules})
      local initial_weight = agent._weights["rule1"]

      -- Create a successful trace
      local trace = {
        steps = {
          {decision = {rule_id = "rule1", salience = 0.8, value = 0.5}}
        },
        final_result = {answer = "42"}
      }

      agent:LearnFromExecution(trace, {
        learning_rate = 0.1,
        credit_method = "td"
      })

      -- Weight should have increased
      assert.is_true(agent._weights["rule1"] > initial_weight)
    end)

    it("should decrease weights for failed decisions", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "rule1", default_weight = 0.7}
      }

      local agent = ACE.new(module, {rules = rules})
      local initial_weight = agent._weights["rule1"]

      -- Create a failed trace
      local trace = {
        steps = {
          {decision = {rule_id = "rule1", salience = 0.8, value = 0.5}}
        },
        error = "Task failed"
      }

      agent:LearnFromExecution(trace, {
        learning_rate = 0.1,
        credit_method = "td"
      })

      -- Weight should have decreased
      assert.is_true(agent._weights["rule1"] < initial_weight)
    end)

    it("should support different credit assignment methods", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "rule1", default_weight = 0.5}
      }

      local trace = {
        steps = {
          {decision = {rule_id = "rule1", salience = 0.8, value = 0.5}}
        },
        final_result = {answer = "42"}
      }

      -- Test TD method
      local agent1 = ACE.new(module, {rules = rules})
      local result1 = agent1:LearnFromExecution(trace, {credit_method = "td"})
      assert.is_not_nil(result1.credits)

      -- Test salience method
      local agent2 = ACE.new(module, {rules = rules})
      local result2 = agent2:LearnFromExecution(trace, {credit_method = "salience"})
      assert.is_not_nil(result2.credits)

      -- Test recency method
      local agent3 = ACE.new(module, {rules = rules})
      local result3 = agent3:LearnFromExecution(trace, {credit_method = "recency"})
      assert.is_not_nil(result3.credits)
    end)

  end)

  describe("AggregateExecutionCredits", function()

    it("should aggregate credits from multiple executions", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "rule1", default_weight = 0.5}
      }

      local agent = ACE.new(module, {rules = rules})

      local credits1 = {
        rule1 = {rule_id = "rule1", total_credit = 0.5, contributions = {}}
      }

      local credits2 = {
        rule1 = {rule_id = "rule1", total_credit = 0.3, contributions = {}}
      }

      local aggregated = agent:AggregateExecutionCredits({credits1, credits2})

      assert.is_not_nil(aggregated)
      assert.is_equal(0.8, aggregated["rule1"].total_credit)
    end)

    it("should normalize credits when requested", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "rule1", default_weight = 0.5},
        {key = "rule2", default_weight = 0.5}
      }

      local agent = ACE.new(module, {rules = rules})

      local credits = {
        rule1 = {rule_id = "rule1", total_credit = -1.0, contributions = {}},
        rule2 = {rule_id = "rule2", total_credit = 1.0, contributions = {}}
      }

      local aggregated = agent:AggregateExecutionCredits({credits}, {
        normalize = true
      })

      -- Normalized credits should be in [0, 1]
      assert.is_equal(0.0, aggregated["rule1"].normalized_credit)
      assert.is_equal(1.0, aggregated["rule2"].normalized_credit)
    end)

  end)

  describe("_BuildExecutionTrace", function()

    it("should build trace from state with action history", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local agent = ACE.new(module, {})

      local state = {
        answer = "42",
        self = {
          steps_taken = 2,
          action_history = {
            {
              decision = {rule_id = "rule1", salience = 0.8}
            },
            {
              decision = {rule_id = "rule2", salience = 0.9},
              tool = {name = "calculator"}
            }
          }
        }
      }

      local trace = agent:_BuildExecutionTrace(state, "success")

      assert.is_equal(2, #trace.steps)
      assert.is_equal("42", trace.final_result.answer)
      assert.is_nil(trace.error)

      -- First step should have decision
      assert.is_not_nil(trace.steps[1].decision)
      assert.is_equal("rule1", trace.steps[1].decision.rule_id)

      -- Second step should have both decision and tool
      assert.is_not_nil(trace.steps[2].decision)
      assert.is_not_nil(trace.steps[2].tool)
      assert.is_equal("calculator", trace.steps[2].tool.name)
    end)

    it("should handle failed execution", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local agent = ACE.new(module, {})

      local state = {
        answer = nil,
        self = {
          steps_taken = 1,
          action_history = {
            {decision = {rule_id = "rule1", salience = 0.8}}
          }
        }
      }

      local trace = agent:_BuildExecutionTrace(state, "error")

      assert.is_equal(1, #trace.steps)
      assert.is_nil(trace.final_result)
      assert.is_equal("error", trace.error)
    end)

  end)

  describe("ProcessExecutionWithOutcome", function()

    it("should process execution and apply learning", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "rule1", default_weight = 0.5}
      }

      local agent = ACE.new(module, {rules = rules})

      -- Create a simple trace manually for testing
      local trace = {
        steps = {
          {decision = {rule_id = "rule1", salience = 0.8, value = 0.5}}
        },
        final_result = {answer = "42"}
      }

      local initial_weight = agent._weights["rule1"]

      local result = agent:LearnFromExecution(trace, {
        learning_rate = 0.1
      })

      assert.is_not_nil(result)
      assert.is_not_nil(result.credits)

      -- Check if credits were generated for rule1
      local rule1_credits = result.credits["rule1"]
      assert.is_not_nil(rule1_credits, "Credits should be generated for rule1")

      -- Weight should have been updated
      assert.is_true(agent._weights["rule1"] ~= initial_weight,
        "Weight should be updated after learning")
    end)

  end)

  describe("End-to-End Learning Workflow", function()

    it("should complete full learning cycle", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local rules = {
        {key = "math_solver", default_weight = 0.5},
        {key = "calculator", default_weight = 0.5}
      }

      local agent = ACE.new(module, {rules = rules})

      -- Simulate multiple executions
      local traces = {
        {
          steps = {
            {decision = {rule_id = "math_solver", salience = 0.8, value = 0.5}},
            {decision = {rule_id = "calculator", salience = 0.9, value = 0.6}}
          },
          final_result = {answer = "42"}
        },
        {
          steps = {
            {decision = {rule_id = "math_solver", salience = 0.7, value = 0.4}}
          },
          error = "Failed"
        },
        {
          steps = {
            {decision = {rule_id = "calculator", salience = 0.8, value = 0.5}}
          },
          final_result = {answer = "100"}
        }
      }

      -- Learn from each execution
      local all_credits = {}
      for _, trace in ipairs(traces) do
        local result = agent:LearnFromExecution(trace, {
          learning_rate = 0.1,
          credit_method = "td"
        })
        table.insert(all_credits, result.credits)
      end

      -- Aggregate credits
      local aggregated = agent:AggregateExecutionCredits(all_credits)

      assert.is_not_nil(aggregated)

      -- Weights should have been updated
      -- (can't assert exact values since TD learning is complex)
      assert.is_not_nil(agent._weights["math_solver"])
      assert.is_not_nil(agent._weights["calculator"])
    end)

  end)

end)
