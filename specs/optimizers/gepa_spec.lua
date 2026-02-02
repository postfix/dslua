-- specs/optimizers/gepa_spec.lua
-- Tests for GEPA Optimizer

describe("GEPA Optimizer", function()
  local GEPA = require("dslua.optimizers.gepa")
  local Predict = require("dslua.modules.predict")
  local Signature = require("dslua.core.signature")
  local Field = require("dslua.core.field")
  local Context = require("dslua.core.context")

  -- Helper to create simple program
  local function createProgram()
    local sig = Signature.new(
      {Field.new("question")},
      {Field.new("answer")}
    )

    return Predict.new(sig)
  end

  -- Helper to create mock trainset
  local function createTrainset()
    return {
      {ctx = Context.new({}), question = "What is 2+2?", answer = "4"},
      {ctx = Context.new({}), question = "What is 3+3?", answer = "6"},
      {ctx = Context.new({}), question = "What is 5+5?", answer = "10"},
      {ctx = Context.new({}), question = "What is 7+7?", answer = "14"},
      {ctx = Context.new({}), question = "What is 10+10?", answer = "20"}
    }
  end

  describe("new", function()
    it("should create GEPA optimizer with program", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {}
      })

      assert.is.equal(program, optimizer._module)
      assert.is.equal(3, optimizer._ensemble_size)
      assert.is.equal(5, optimizer._max_demonstrations_per_model)
      assert.is.equal("majority_vote", optimizer._aggregation_strategy)
    end)

    it("should accept custom options", function()
      local program = createProgram()
      local optimizer = GEPA.new(program, {
        ensemble_size = 5,
        max_demonstrations_per_model = 3,
        aggregation_strategy = "weighted",
        max_trials = 15
      })

      assert.is.equal(5, optimizer._ensemble_size)
      assert.is.equal(3, optimizer._max_demonstrations_per_model)
      assert.is.equal("weighted", optimizer._aggregation_strategy)
      assert.is.equal(15, optimizer._max_trials)
    end)
  end)

  describe("Compile", function()
    it("should compile with trainset", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {},
        ensemble_size = 2
      })

      local ctx = Context.new({})

      local ensemble_program, metrics = optimizer:Compile(ctx, 3)

      assert.is.truthy(ensemble_program)
      assert.is.truthy(ensemble_program.Process)
      assert.is.equal(2, metrics.ensemble_size)
      assert.is.equal(2, #metrics.weights)
    end)

    it("should handle empty trainset", function()
      local program = createProgram()
      local optimizer = GEPA.new(program, {
        trainset = {},
        valset = {}
      })

      local ctx = Context.new({})

      local ensemble_program, metrics = optimizer:Compile(ctx)

      assert.is.truthy(ensemble_program)
      assert.is.equal(0, metrics.ensemble_size)
    end)

    it("should handle single example trainset", function()
      local program = createProgram()
      local trainset = {
        {ctx = Context.new({}), question = "Single", answer = "Answer"}
      }

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {},
        ensemble_size = 2
      })

      local ctx = Context.new({})

      local ensemble_program, metrics = optimizer:Compile(ctx)

      assert.is.truthy(ensemble_program)
      assert.is.equal(2, metrics.ensemble_size)
    end)

    it("should generate ensemble with diverse subsets", function()
      local program = createProgram()
      local trainset = {
        {ctx = Context.new({}), question = "Math 1", answer = "A"},
        {ctx = Context.new({}), question = "Math 2", answer = "B"},
        {ctx = Context.new({}), question = "History 1", answer = "C"},
        {ctx = Context.new({}), question = "History 2", answer = "D"}
      }

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {},
        ensemble_size = 3,
        max_demonstrations_per_model = 2
      })

      local ctx = Context.new({})
      local ensemble_program, metrics = optimizer:Compile(ctx, 2)

      assert.is.truthy(ensemble_program)
      assert.is.equal(3, metrics.ensemble_size)
    end)
  end)

  describe("_selectDiverseSubset", function()
    it("should select subset with given size", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {},
        max_demonstrations_per_model = 3
      })

      local subset = optimizer:_selectDiverseSubset(1)

      assert.is.equal(3, #subset)
    end)

    it("should handle trainset smaller than subset size", function()
      local program = createProgram()
      local trainset = {
        {ctx = Context.new({}), question = "A", answer = "1"}
      }

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {},
        max_demonstrations_per_model = 5
      })

      local subset = optimizer:_selectDiverseSubset(1)

      assert.is.equal(1, #subset)
    end)
  end)

  describe("_calculateWeights", function()
    it("should calculate equal weights for majority_vote", function()
      local program = createProgram()
      local optimizer = GEPA.new(program, {
        aggregation_strategy = "majority_vote"
      })

      local ensemble = {
        {model = {}, demonstrations = {1, 2}},
        {model = {}, demonstrations = {3, 4}}
      }

      local weights = optimizer:_calculateWeights(ensemble)

      assert.is.equal(2, #weights)
      assert.is.equal(1.0, weights[1])
      assert.is.equal(1.0, weights[2])
    end)

    it("should calculate equal weights for weighted", function()
      local program = createProgram()
      local optimizer = GEPA.new(program, {
        aggregation_strategy = "weighted"
      })

      local ensemble = {
        {model = {}, demonstrations = {1, 2}},
        {model = {}, demonstrations = {3, 4}}
      }

      local weights = optimizer:_calculateWeights(ensemble)

      assert.is.equal(2, #weights)
      assert.is.equal(0.5, weights[1])
      assert.is.equal(0.5, weights[2])
    end)

    it("should calculate demo-based weights for confidence", function()
      local program = createProgram()
      local optimizer = GEPA.new(program, {
        aggregation_strategy = "confidence"
      })

      local ensemble = {
        {model = {}, demonstrations = {1, 2, 3}},  -- 3 demos
        {model = {}, demonstrations = {4}}  -- 1 demo
      }

      local weights = optimizer:_calculateWeights(ensemble)

      assert.is.equal(2, #weights)
      assert.is.truthy(weights[1] > weights[2])  -- More demos = higher weight
      assert.is.equal(0.75, weights[1])
      assert.is.equal(0.25, weights[2])
    end)
  end)

  describe("_majorityVote", function()
    it("should select majority answer", function()
      local program = createProgram()
      local optimizer = GEPA.new(program)

      local predictions = {
        {answer = "A", question = "Q"},
        {answer = "A", question = "Q"},
        {answer = "B", question = "Q"}
      }

      local result = optimizer:_majorityVote(predictions)

      assert.is.equal("A", result.answer)
    end)

    it("should handle tie by selecting first", function()
      local program = createProgram()
      local optimizer = GEPA.new(program)

      local predictions = {
        {answer = "A", question = "Q"},
        {answer = "B", question = "Q"}
      }

      local result = optimizer:_majorityVote(predictions)

      assert.is.truthy(result.answer == "A" or result.answer == "B")
    end)

    it("should handle empty predictions", function()
      local program = createProgram()
      local optimizer = GEPA.new(program)

      local predictions = {}

      local result = optimizer:_majorityVote(predictions)

      assert.is.equal(0, #result)  -- Empty table
    end)
  end)

  describe("_weightedAggregation", function()
    it("should aggregate with weights", function()
      local program = createProgram()
      local optimizer = GEPA.new(program)

      local predictions = {
        {answer = "A", question = "Q"},
        {answer = "B", question = "Q"},
        {answer = "B", question = "Q"}
      }

      local weights = {0.5, 0.3, 0.2}

      local result = optimizer:_weightedAggregation(predictions, weights)

      -- B has higher combined weight (0.3 + 0.2 = 0.5) vs A (0.5)
      -- Actually they tie at 0.5, so either could win
      assert.is.truthy(result.answer == "A" or result.answer == "B")
    end)

    it("should handle equal weights", function()
      local program = createProgram()
      local optimizer = GEPA.new(program)

      local predictions = {
        {answer = "A", question = "Q"},
        {answer = "A", question = "Q"},
        {answer = "B", question = "Q"}
      }

      local weights = {0.33, 0.33, 0.33}

      local result = optimizer:_weightedAggregation(predictions, weights)

      assert.is.equal("A", result.answer)  -- A appears twice
    end)
  end)

  describe("_demoSignature", function()
    it("should create unique signature for demo", function()
      local program = createProgram()
      local optimizer = GEPA.new(program)

      local demo1 = {question = "Test", answer = "A"}
      local demo2 = {question = "Test", answer = "B"}

      local sig1 = optimizer:_demoSignature(demo1)
      local sig2 = optimizer:_demoSignature(demo2)

      assert.is_not.equal(sig1, sig2)
    end)

    it("should create same signature for identical demo", function()
      local program = createProgram()
      local optimizer = GEPA.new(program)

      local demo1 = {question = "Test", answer = "A"}
      local demo2 = {question = "Test", answer = "A"}

      local sig1 = optimizer:_demoSignature(demo1)
      local sig2 = optimizer:_demoSignature(demo2)

      assert.is.equal(sig1, sig2)
    end)
  end)

  describe("GetEnsemble", function()
    it("should return ensemble after compilation", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {}
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local ensemble = optimizer:GetEnsemble()

      assert.is.truthy(ensemble)
      assert.is_truthy(#ensemble > 0)
    end)
  end)

  describe("GetWeights", function()
    it("should return weights after compilation", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {}
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local weights = optimizer:GetWeights()

      assert.is.truthy(weights)
      assert.is_truthy(#weights > 0)
    end)
  end)

  describe("GetBestScore", function()
    it("should return best score after compilation", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {}
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local score = optimizer:GetBestScore()

      assert.is.truthy(score >= 0)
    end)
  end)

  describe("GetEnsembleSize", function()
    it("should return ensemble size", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {},
        ensemble_size = 4
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local size = optimizer:GetEnsembleSize()

      assert.is.equal(4, size)
    end)
  end)

  describe("AnalyzeEnsemble", function()
    it("should analyze ensemble characteristics", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {},
        ensemble_size = 3,
        max_demonstrations_per_model = 3
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local analysis = optimizer:AnalyzeEnsemble()

      assert.is.equal(3, analysis.size)
      assert.is.truthy(analysis.total_demonstrations > 0)
      assert.is.truthy(analysis.avg_demonstrations > 0)
      assert.is.truthy(analysis.diversity_score >= 0 and analysis.diversity_score <= 1)
    end)

    it("should handle empty ensemble", function()
      local program = createProgram()
      local optimizer = GEPA.new(program, {
        trainset = {},
        valset = {}
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local analysis = optimizer:AnalyzeEnsemble()

      assert.is.equal(0, analysis.size)
      assert.is.equal(0, analysis.total_demonstrations)
    end)
  end)

  describe("Integration Tests", function()
    it("should create ensemble program structure", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {},
        ensemble_size = 2,
        aggregation_strategy = "majority_vote"
      })

      local ctx = Context.new({})
      local ensemble_program, metrics = optimizer:Compile(ctx, 3)

      -- Verify ensemble program structure
      assert.is.truthy(ensemble_program)
      assert.is.truthy(ensemble_program._ensemble)
      assert.is.truthy(ensemble_program.Process)  -- Has Process method
      assert.is.equal(2, metrics.ensemble_size)
    end)

    it("should work with weighted aggregation", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {},
        ensemble_size = 3,
        aggregation_strategy = "weighted"
      })

      local ctx = Context.new({})
      local ensemble_program, metrics = optimizer:Compile(ctx, 2)

      assert.is.equal(3, metrics.ensemble_size)
      assert.is.equal(3, #metrics.weights)
    end)

    it("should work with confidence aggregation", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {},
        ensemble_size = 2,
        aggregation_strategy = "confidence"
      })

      local ctx = Context.new({})
      local ensemble_program, metrics = optimizer:Compile(ctx, 2)

      assert.is.equal(2, metrics.ensemble_size)
    end)

    it("should handle large datasets efficiently", function()
      local program = createProgram()

      -- Create larger dataset
      local trainset = {}
      for i = 1, 20 do
        table.insert(trainset, {
          ctx = Context.new({}),
          question = "Question " .. i,
          answer = "Answer " .. i
        })
      end

      local optimizer = GEPA.new(program, {
        trainset = trainset,
        valset = {},
        ensemble_size = 3,
        max_demonstrations_per_model = 5
      })

      local ctx = Context.new({})
      local start_time = os.clock()
      local ensemble_program, metrics = optimizer:Compile(ctx, 3)
      local elapsed = os.clock() - start_time

      assert.is.truthy(metrics.ensemble_size > 0)
      assert.is.truthy(elapsed < 10)  -- Should complete in reasonable time
    end)
  end)
end)
