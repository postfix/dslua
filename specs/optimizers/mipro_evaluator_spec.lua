-- specs/optimizers/mipro_evaluator_spec.lua
-- Tests for MIPRO Evaluator Module

local Evaluator = require("dslua.optimizers.mipro_evaluator")
local Signature = require("dslua.core.signature")
local Field = require("dslua.core.field")
local Predict = require("dslua.modules.predict")

describe("MIPRO Evaluator Module", function()

  describe("EvaluateProgram", function()

    it("should evaluate program on validation set", function()
      local call_count = 0
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          call_count = call_count + 1
          -- Return answers in sequence: 4, 6, 10
          -- Match expected output format {answer = "..."}
          local answers = {"4", "6", "10"}
          return {answer = answers[call_count]}
        end
      }

      local module = Predict.new(signature)
      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local valset = {
        {input = {question = "2+2"}, output = {answer = "4"}},
        {input = {question = "3+3"}, output = {answer = "6"}},
        {input = {question = "5+5"}, output = {answer = "10"}}
      }

      local metrics = Evaluator.EvaluateProgram(module, valset, ctx, {})

      assert.is_not_nil(metrics)
      assert.is_equal(3, metrics.total_examples)
      assert.is_equal(3, metrics.correct_count)
      assert.is_equal(1.0, metrics.accuracy)
    end)

    it("should track individual results", function()
      local call_count = 0
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          call_count = call_count + 1
          -- First correct, second wrong
          -- Match expected output format {answer = "..."}
          local answers = {"42", "100"}
          return {answer = answers[call_count]}
        end
      }

      local module = Predict.new(signature)
      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local valset = {
        {input = {question = "Q1"}, output = {answer = "42"}},
        {input = {question = "Q2"}, output = {answer = "42"}}  -- Wrong, expected 100
      }

      local metrics = Evaluator.EvaluateProgram(module, valset, ctx, {})

      assert.is_equal(2, #metrics.results)
      assert.is_true(metrics.results[1].correct)
      assert.is_false(metrics.results[2].correct)
    end)

    it("should use custom metric function when provided", function()
      local signature = Signature.new(
        {Field.new("text")},
        {Field.new("summary")}
      )
      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {summary = "Summarized text"}
        end
      }

      local module = Predict.new(signature)
      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local valset = {
        {input = {text = "Long text"}, output = {summary = "Summary"}}
      }

      local custom_metric = function(results)
        -- Custom metric: count results with non-empty output
        local count = 0
        for _, r in ipairs(results) do
          if r.output and r.output.summary and #r.output.summary > 0 then
            count = count + 1
          end
        end
        return count / #results
      end

      local metrics = Evaluator.EvaluateProgram(module, valset, ctx, {
        metric_fn = custom_metric
      })

      assert.is_not_nil(metrics.custom_score)
      assert.is_true(metrics.custom_score >= 0 and metrics.custom_score <= 1.0)
    end)

  end)

  describe("ComputeScore", function()

    it("should compute weighted score from metrics", function()
      local metrics = {
        accuracy = 0.8,
        latency = 100,  -- ms
        total_examples = 10
      }

      local weights = {
        accuracy = 1.0,
        latency = -0.001  -- Penalize high latency
      }

      local score = Evaluator.ComputeScore(metrics, weights)

      -- Score = 0.8 * 1.0 + 100 * -0.001 = 0.8 - 0.1 = 0.7
      assert.is_true(score >= 0.69 and score <= 0.71)
    end)

    it("should handle missing metric fields", function()
      local metrics = {
        accuracy = 0.75
        -- latency missing
      }

      local weights = {
        accuracy = 1.0,
        latency = -0.001
      }

      local score = Evaluator.ComputeScore(metrics, weights)

      -- Should only include accuracy
      assert.is_equal(0.75, score)
    end)

    it("should normalize by total weight", function()
      local metrics = {
        accuracy = 0.8,
        custom_score = 0.6
      }

      local weights = {
        accuracy = 1.0,
        custom_score = 1.0
      }

      local score = Evaluator.ComputeScore(metrics, weights)

      -- (0.8 + 0.6) / 2 = 0.7
      assert.is_true(score >= 0.69 and score <= 0.71)
    end)

    it("should return 0 for empty metrics", function()
      local score = Evaluator.ComputeScore({}, {})
      assert.is_equal(0, score)
    end)

  end)

end)
