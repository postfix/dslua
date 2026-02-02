-- specs/agents/ace_outcome_spec.lua
-- Tests for ACE Phase 3: Outcome Tracking & Classification

local Outcome = require("dslua.agents.ace_outcome")

describe("ACE Outcome - Classification", function()

  describe("ClassifyOutcome", function()

    it("classifies successful execution with valid result", function()
      local trace = {
        steps = {
          {action = "REASON", thought = "Let me calculate"},
          {action = "USE_CALCULATOR", args = {operation = "15*27"}},
          {action = "TERMINATE"}
        },
        final_result = {
          answer = "405",
          confidence = 0.9
        },
        error = nil,
        steps_taken = 3,
        duration_ms = 150
      }

      local outcome = Outcome.ClassifyOutcome(trace, {
        min_confidence = 0.7,
        max_steps = 10
      })

      assert.is_true(outcome.success)
      assert.is_equal(0.9, outcome.confidence)
      assert.is_equal("valid_result", outcome.reason)
    end)

    it("classifies failure when error present", function()
      local trace = {
        steps = {
          {action = "REASON", thought = "Let me calculate"}
        },
        final_result = nil,
        error = "Calculator tool failed",
        steps_taken = 1,
        duration_ms = 50
      }

      local outcome = Outcome.ClassifyOutcome(trace, {
        min_confidence = 0.7,
        max_steps = 10
      })

      assert.is_false(outcome.success)
      assert.is_equal(0.0, outcome.confidence)
      assert.is_equal("execution_error", outcome.reason)
    end)

    it("classifies failure when confidence too low", function()
      local trace = {
        steps = {
          {action = "REASON", thought = "Not sure"}
        },
        final_result = {
          answer = "Maybe 42?",
          confidence = 0.3
        },
        error = nil,
        steps_taken = 1,
        duration_ms = 50
      }

      local outcome = Outcome.ClassifyOutcome(trace, {
        min_confidence = 0.7,
        max_steps = 10
      })

      assert.is_false(outcome.success)
      assert.is_equal(0.3, outcome.confidence)
      assert.is_equal("low_confidence", outcome.reason)
    end)

    it("classifies failure when steps exceed max", function()
      local trace = {
        steps = {},
        final_result = {
          answer = "405",
          confidence = 0.9
        },
        error = nil,
        steps_taken = 15,
        duration_ms = 500
      }

      local outcome = Outcome.ClassifyOutcome(trace, {
        min_confidence = 0.7,
        max_steps = 10
      })

      assert.is_false(outcome.success)
      assert.is_equal(0.0, outcome.confidence)
      assert.is_equal("max_steps_exceeded", outcome.reason)
    end)

    it("uses custom success function when provided", function()
      local trace = {
        steps = {},
        final_result = {answer = "42"},
        error = nil,
        steps_taken = 1
      }

      local custom_fn = function(t)
        return t.final_result.answer == "42", 1.0, "correct_answer"
      end

      local outcome = Outcome.ClassifyOutcome(trace, {
        custom_success_fn = custom_fn
      })

      assert.is_true(outcome.success)
      assert.is_equal(1.0, outcome.confidence)
      assert.is_equal("correct_answer", outcome.reason)
    end)

  end)

  describe("ExtractFeatures", function()

    it("extracts features from execution trace", function()
      local trace = {
        state_snapshot = {
          task = {
            task_type = "math",
            complexity_estimate = 0.8,
            input_length = 15.0,
            entity_count = 2.0,
            tool_requirements = {"calculator"}
          },
          self = {
            confidence = 0.5,
            steps_taken = 0
          }
        },
        actions = {"REASON", "USE_CALCULATOR", "VERIFY", "TERMINATE"},
        tool_usage = {
          calculator = 1
        },
        confidence_trajectory = {0.5, 0.6, 0.9, 0.9},
        steps_taken = 4,
        duration_ms = 200
      }

      local features = Outcome.ExtractFeatures(trace)

      assert.is_equal("math", features.task_type)
      assert.is_equal(0.8, features.complexity_estimate)
      assert.is_equal(4, features.steps_taken)
      assert.is_equal(1, features.tool_usage.calculator)
      assert.is_equal("REASON", features.actions[1])
    end)

    it("handles missing optional features gracefully", function()
      local trace = {
        state_snapshot = {
          task = {task_type = "factual"},
          self = {}
        },
        actions = {"REASON"},
        steps_taken = 1
      }

      local features = Outcome.ExtractFeatures(trace)

      assert.is_equal("factual", features.task_type)
      assert.is_equal(1, features.steps_taken)
      assert.is_nil(features.complexity_estimate)
      assert.is_same({}, features.tool_usage or {})
    end)

  end)

end)
