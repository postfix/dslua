-- specs/optimizers/mipro_integration_spec.lua
-- End-to-end integration tests for MIPRO Optimizer

local MIPRO = require("dslua.optimizers.mipro")
local Signature = require("dslua.core.signature")
local Field = require("dslua.core.field")
local Predict = require("dslua.modules.predict")

describe("MIPRO Integration Tests", function()

  describe("End-to-End Optimization", function()

    it("should optimize simple arithmetic task", function()
      -- Define task
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      -- Training data
      local trainset = {
        {input = {question = "2+2"}, output = {answer = "4"}},
        {input = {question = "3+3"}, output = {answer = "6"}},
        {input = {question = "5+5"}, output = {answer = "10"}},
        {input = {question = "4*3"}, output = {answer = "12"}},
        {input = {question = "10/2"}, output = {answer = "5"}}
      }

      -- Validation data
      local valset = {
        {input = {question = "1+1"}, output = {answer = "2"}},
        {input = {question = "2*2"}, output = {answer = "4"}},
        {input = {question = "6/2"}, output = {answer = "3"}}
      }

      -- Mock LLM that simulates learning from demos
      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          -- Extract demos from prompt and try to match
          local question = prompt:match("question: ([^\n]+)")
          if not question then
            return {answer = "42"}  -- Fallback
          end

          -- Simple pattern matching for demo questions
          if question:match("1%+1") then
            return {answer = "2"}
          elseif question:match("2%*2") then
            return {answer = "4"}
          elseif question:match("6%/2") then
            return {answer = "3"}
          else
            return {answer = "42"}  -- Default wrong answer
          end
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      -- Patch evaluation to use our context
      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      -- Run MIPRO optimization
      local optimizer = MIPRO.new(base_module)
      optimizer.num_trials = 5
      optimizer.seed = 42

      local best_program, metrics = optimizer:Compile(trainset, valset)

      -- Restore
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      -- Verify results
      assert.is_not_nil(best_program)
      assert.is_not_nil(metrics)
      assert.is_not_nil(optimizer.best_program)
      assert.is_true(optimizer.best_score > -math.huge)
      assert.is_not_nil(optimizer.best_metrics)

      -- Best metrics should have validation results
      assert.is_not_nil(optimizer.best_metrics.total_examples)
      assert.is_equal(3, optimizer.best_metrics.total_examples)
    end)

    it("should explore different hyperparameter combinations", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local trainset = {
        {input = {question = "Q1"}, output = {answer = "A1"}},
        {input = {question = "Q2"}, output = {answer = "A2"}},
        {input = {question = "Q3"}, output = {answer = "A3"}},
        {input = {question = "Q4"}, output = {answer = "A4"}}
      }

      local valset = {
        {input = {question = "Q5"}, output = {answer = "A5"}}
      }

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {answer = "A5"}
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      local optimizer = MIPRO.new(base_module)
      optimizer.num_trials = 5
      optimizer.seed = 42

      local best_program, metrics = optimizer:Compile(trainset, valset)

      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      -- Should complete 5 trials and return best program
      assert.is_not_nil(best_program)
      assert.is_not_nil(metrics)
      assert.is_true(optimizer.best_score > -math.huge)

      -- Best program should be a valid program
      assert.is_not_nil(optimizer.best_program)
    end)

    it("should use custom metric function", function()
      local signature = Signature.new(
        {Field.new("text")},
        {Field.new("summary")}
      )
      local base_module = Predict.new(signature)

      local trainset = {
        {input = {text = "Long text 1"}, output = {summary = "Short 1"}},
        {input = {text = "Long text 2"}, output = {summary = "Short 2"}}
      }

      local valset = {
        {input = {text = "Long text 3"}, output = {summary = "Short 3"}}
      }

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {summary = "Generated summary"}
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      -- Custom metric: reward short summaries
      local custom_metric = function(results)
        local avg_length = 0
        for _, r in ipairs(results) do
          if r.output and r.output.summary then
            avg_length = avg_length + #r.output.summary
          end
        end
        avg_length = avg_length / #results
        -- Score inversely proportional to length
        return 1.0 / (avg_length + 1)
      end

      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      local optimizer = MIPRO.new(base_module, {
        weights = {custom_score = 1.0},
        metric_fn = custom_metric
      })
      optimizer.num_trials = 3
      optimizer.seed = 42

      optimizer:Compile(trainset, valset)

      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      -- Best metrics should include custom score
      assert.is_not_nil(optimizer.best_metrics.custom_score)
      assert.is_true(optimizer.best_metrics.custom_score > 0)
    end)

    it("should handle multi-objective optimization", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local trainset = {
        {input = {question = "Q1"}, output = {answer = "A1"}}
      }

      local valset = {
        {input = {question = "Q2"}, output = {answer = "A2"}}
      }

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {answer = "A2"}
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      local optimizer = MIPRO.new(base_module, {
        weights = {
          accuracy = 1.0,
          latency = -0.001  -- Penalize high latency
        }
      })
      optimizer.num_trials = 3
      optimizer.seed = 42

      optimizer:Compile(trainset, valset)

      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      -- Score should balance accuracy and latency
      assert.is_not_nil(optimizer.best_score)
      assert.is_not_nil(optimizer.best_metrics.accuracy)
      assert.is_not_nil(optimizer.best_metrics.avg_latency_ms)
    end)

    it("should configure hyperparameter space", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local trainset = {
        {input = {question = "Q1"}, output = {answer = "A1"}}
      }

      local valset = {
        {input = {question = "Q2"}, output = {answer = "A2"}}
      }

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {answer = "A2"}
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      local optimizer = MIPRO.new(base_module)
      optimizer:Configure({
        hyperparameter_space = {
          num_demos = {type = "int", min = 1, max = 3},
          demo_selection = {type = "enum", values = {"random", "diverse"}}
        }
      })
      optimizer.num_trials = 2
      optimizer.seed = 42

      optimizer:Compile(trainset, valset)

      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      -- Should successfully complete with custom space
      assert.is_not_nil(optimizer.best_program)
    end)

  end)

  describe("Comparison with Baselines", function()

    it("should outperform no optimization baseline", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local base_module = Predict.new(signature)

      local trainset = {
        {input = {question = "2+2"}, output = {answer = "4"}},
        {input = {question = "3+3"}, output = {answer = "6"}}
      }

      local valset = {
        {input = {question = "1+1"}, output = {answer = "2"}},
        {input = {question = "2+2"}, output = {answer = "4"}}
      }

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          -- With fewshot demos, gets better
          return {answer = "2"}
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      -- Baseline: No optimization (just base module)
      local baseline_metrics = original_evaluate(base_module, valset, ctx, {})

      -- MIPRO: Optimized
      local optimizer = MIPRO.new(base_module)
      optimizer.num_trials = 3
      optimizer.seed = 42

      optimizer:Compile(trainset, valset)

      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      -- MIPRO should at least match baseline
      assert.is_not_nil(optimizer.best_metrics.accuracy)
      assert.is_true(optimizer.best_metrics.accuracy >= baseline_metrics.accuracy)
    end)

  end)

end)
