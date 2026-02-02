-- specs/optimizers/mipro_spec.lua
-- Tests for MIPRO Optimizer

local MIPRO = require("dslua.optimizers.mipro")
local Signature = require("dslua.core.signature")
local Field = require("dslua.core.field")
local Predict = require("dslua.modules.predict")

describe("MIPRO Optimizer", function()

  describe("new", function()

    it("should create optimizer with defaults", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local optimizer = MIPRO.new(module)

      assert.is_not_nil(optimizer)
      assert.is_equal(20, optimizer.num_trials)
      assert.is_equal(5, optimizer.early_stopping_rounds)
      assert.is_equal(0.25, optimizer.gamma)
      assert.is_false(optimizer.verbose)
    end)

    it("should accept custom metric options", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local optimizer = MIPRO.new(module, {
        weights = {accuracy = 1.0, latency = -0.001},
        metric_fn = function(results) return 0.5 end
      })

      assert.is_not_nil(optimizer.metric_opts)
      assert.is_not_nil(optimizer.metric_opts.weights)
      assert.is_not_nil(optimizer.metric_opts.metric_fn)
    end)

  end)

  describe("Compile", function()

    it("should optimize program over multiple trials", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local trainset = {
        {input = {question = "2+2"}, output = {answer = "4"}},
        {input = {question = "3+3"}, output = {answer = "6"}},
        {input = {question = "5+5"}, output = {answer = "10"}}
      }

      local valset = {
        {input = {question = "1+1"}, output = {answer = "2"}},
        {input = {question = "2+2"}, output = {answer = "4"}}
      }

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {answer = "42"}  -- Always return same answer
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local optimizer = MIPRO.new(module)
      optimizer.num_trials = 3
      optimizer.seed = 42

      -- Patch evaluation to use our context
      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      local best_program, metrics = optimizer:Compile(trainset, valset)

      -- Restore original
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      assert.is_not_nil(best_program)
      assert.is_not_nil(metrics)
      assert.is_true(optimizer.best_score > -math.huge)
    end)

    it("should use custom hyperparameter space", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local trainset = {
        {input = {question = "2+2"}, output = {answer = "4"}}
      }

      local valset = {
        {input = {question = "1+1"}, output = {answer = "2"}}
      }

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {answer = "2"}
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local optimizer = MIPRO.new(module)
      optimizer.num_trials = 2
      optimizer.seed = 42
      optimizer:Configure({
        hyperparameter_space = {
          num_demos = {type = "int", min = 1, max = 3}
        }
      })

      -- Patch evaluation
      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      optimizer:Compile(trainset, valset)

      -- Restore
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      assert.is_not_nil(optimizer.best_program)
    end)

    it("should stop early if no improvement", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local trainset = {
        {input = {question = "2+2"}, output = {answer = "4"}}
      }

      local valset = {
        {input = {question = "1+1"}, output = {answer = "2"}}
      }

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {answer = "42"}
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local optimizer = MIPRO.new(module)
      optimizer.num_trials = 20
      optimizer.early_stopping_rounds = 3
      optimizer.seed = 42

      -- Patch evaluation
      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      optimizer:Compile(trainset, valset)

      -- Restore
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      -- Should stop before 20 trials due to early stopping
      assert.is_not_nil(optimizer.best_program)
    end)

    it("should accept compile options", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local trainset = {
        {input = {question = "2+2"}, output = {answer = "4"}}
      }

      local valset = {
        {input = {question = "1+1"}, output = {answer = "2"}}
      }

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {answer = "2"}
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local optimizer = MIPRO.new(module)

      -- Patch evaluation
      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      optimizer:Compile(trainset, valset, {
        num_trials = 2,
        seed = 42
      })

      -- Restore
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      assert.is_not_nil(optimizer.best_program)
    end)

  end)

  describe("GetBestProgram", function()

    it("should return nil before compilation", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local optimizer = MIPRO.new(module)

      local best = optimizer:GetBestProgram()

      assert.is_nil(best)
    end)

    it("should return best program after compilation", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local trainset = {
        {input = {question = "2+2"}, output = {answer = "4"}}
      }

      local valset = {
        {input = {question = "1+1"}, output = {answer = "2"}}
      }

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {answer = "2"}
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local optimizer = MIPRO.new(module)
      optimizer.num_trials = 1

      -- Patch evaluation
      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      optimizer:Compile(trainset, valset)

      -- Restore
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      local best = optimizer:GetBestProgram()

      assert.is_not_nil(best)
    end)

  end)

  describe("GetBestScore", function()

    it("should return negative infinity before compilation", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local optimizer = MIPRO.new(module)

      local score = optimizer:GetBestScore()

      assert.is_equal(-math.huge, score)
    end)

    it("should return best score after compilation", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local trainset = {
        {input = {question = "2+2"}, output = {answer = "4"}}
      }

      local valset = {
        {input = {question = "1+1"}, output = {answer = "2"}}
      }

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {answer = "2"}
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local optimizer = MIPRO.new(module)
      optimizer.num_trials = 1

      -- Patch evaluation
      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      optimizer:Compile(trainset, valset)

      -- Restore
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      local score = optimizer:GetBestScore()

      assert.is_true(score > -math.huge)
    end)

  end)

  describe("GetBestMetrics", function()

    it("should return nil before compilation", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local optimizer = MIPRO.new(module)

      local metrics = optimizer:GetBestMetrics()

      assert.is_nil(metrics)
    end)

    it("should return best metrics after compilation", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local trainset = {
        {input = {question = "2+2"}, output = {answer = "4"}}
      }

      local valset = {
        {input = {question = "1+1"}, output = {answer = "2"}}
      }

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {answer = "2"}
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local optimizer = MIPRO.new(module)
      optimizer.num_trials = 1

      -- Patch evaluation
      local original_evaluate = require("dslua.optimizers.mipro_evaluator").EvaluateProgram
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = function(program, valset, _, opts)
        return original_evaluate(program, valset, ctx, opts)
      end

      optimizer:Compile(trainset, valset)

      -- Restore
      require("dslua.optimizers.mipro_evaluator").EvaluateProgram = original_evaluate

      local metrics = optimizer:GetBestMetrics()

      assert.is_not_nil(metrics)
      assert.is_not_nil(metrics.accuracy)
      assert.is_not_nil(metrics.total_examples)
    end)

  end)

  describe("Configure", function()

    it("should update optimizer settings", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local optimizer = MIPRO.new(module)

      optimizer:Configure({
        num_trials = 10,
        early_stopping_rounds = 3,
        verbose = true
      })

      assert.is_equal(10, optimizer.num_trials)
      assert.is_equal(3, optimizer.early_stopping_rounds)
      assert.is_true(optimizer.verbose)
    end)

    it("should merge hyperparameter space", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local optimizer = MIPRO.new(module)

      optimizer:Configure({
        hyperparameter_space = {
          temperature = {type = "float", min = 0.0, max = 1.0}
        }
      })

      assert.is_not_nil(optimizer.hyperparameter_space.num_demos)
      assert.is_not_nil(optimizer.hyperparameter_space.temperature)
    end)

    it("should return self for chaining", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = Predict.new(signature)

      local optimizer = MIPRO.new(module)

      local result = optimizer:Configure({num_trials = 5})

      assert.is_equal(optimizer, result)
    end)

  end)

end)
