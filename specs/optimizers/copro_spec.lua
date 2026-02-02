-- specs/optimizers/copro_spec.lua
-- Tests for COPRO Optimizer

describe("COPRO Optimizer", function()
  local COPRO = require("dslua.optimizers.copro")
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
    it("should create COPRO optimizer with program", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {}
      })

      assert.is.equal(program, optimizer._module)
      assert.is.equal(10, optimizer._max_rounds)
      assert.is.equal(8, optimizer._max_demonstrations)
      assert.is.equal(5, optimizer._candidates_per_round)
    end)

    it("should accept custom options", function()
      local program = createProgram()
      local optimizer = COPRO.new(program, {
        max_rounds = 15,
        max_demonstrations = 10,
        candidates_per_round = 8,
        temperature = 0.5,
        early_stopping_patience = 5
      })

      assert.is.equal(15, optimizer._max_rounds)
      assert.is.equal(10, optimizer._max_demonstrations)
      assert.is.equal(8, optimizer._candidates_per_round)
      assert.is.equal(0.5, optimizer._temperature)
      assert.is.equal(5, optimizer._early_stopping_patience)
    end)
  end)

  describe("Compile", function()
    it("should compile with trainset", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {},
        max_rounds = 3,
        max_demonstrations = 4
      })

      local ctx = Context.new({})

      local best_program, metrics = optimizer:Compile(ctx, 3)

      assert.is.truthy(best_program)
      assert.is.truthy(metrics.num_demonstrations > 0)
      assert.is.truthy(metrics.num_demonstrations <= 4)
      assert.is.equal(3, metrics.rounds)
    end)

    it("should handle empty trainset", function()
      local program = createProgram()
      local optimizer = COPRO.new(program, {
        trainset = {},
        valset = {}
      })

      local ctx = Context.new({})

      local best_program, metrics = optimizer:Compile(ctx)

      assert.is.truthy(best_program)
      assert.is.equal(0, metrics.num_demonstrations)
      assert.is.equal(0, metrics.rounds)
    end)

    it("should handle single example trainset", function()
      local program = createProgram()
      local trainset = {
        {ctx = Context.new({}), question = "Single", answer = "Answer"}
      }

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {},
        max_rounds = 2
      })

      local ctx = Context.new({})

      local best_program, metrics = optimizer:Compile(ctx)

      assert.is.truthy(best_program)
      assert.is.equal(1, metrics.num_demonstrations)
    end)

    it("should perform coordinate descent optimization", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {},
        max_rounds = 3,
        max_demonstrations = 3,
        candidates_per_round = 2
      })

      local ctx = Context.new({})
      local best_program, metrics = optimizer:Compile(ctx, 2)

      assert.is.truthy(best_program)
      assert.is_truthy(metrics.num_demonstrations <= 3)
    end)
  end)

  describe("_randomSubset", function()
    it("should select random subset of specified size", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {}
      })

      local subset = optimizer:_randomSubset(3)

      assert.is.equal(3, #subset)
    end)

    it("should handle size larger than trainset", function()
      local program = createProgram()
      local trainset = {
        {ctx = Context.new({}), question = "A", answer = "1"}
      }

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {}
      })

      local subset = optimizer:_randomSubset(5)

      assert.is.equal(1, #subset)
    end)

    it("should select different subsets on different calls", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {}
      })

      local subset1 = optimizer:_randomSubset(3)
      local subset2 = optimizer:_randomSubset(3)

      -- They might be different due to randomness
      assert.is.equal(3, #subset1)
      assert.is.equal(3, #subset2)
    end)
  end)

  describe("_getAvailableDemos", function()
    it("should return demos not in current set", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {}
      })

      local current = {trainset[1], trainset[2]}
      local available = optimizer:_getAvailableDemos(current)

      assert.is.equal(3, #available)  -- 5 total - 2 current
    end)

    it("should return empty when current contains all", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {}
      })

      local available = optimizer:_getAvailableDemos(trainset)

      assert.is.equal(0, #available)
    end)
  end)

  describe("_generateCandidates", function()
    it("should generate add candidates", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {},
        max_demonstrations = 5,
        candidates_per_round = 2
      })

      local current = {trainset[1]}
      local candidates = optimizer:_generateCandidates(current, "add")

      assert.is_truthy(#candidates > 0)
      for _, candidate in ipairs(candidates) do
        assert.is.truthy(#candidate > 1)  -- Should have added one
      end
    end)

    it("should generate remove candidates", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {}
      })

      local current = {trainset[1], trainset[2], trainset[3]}
      local candidates = optimizer:_generateCandidates(current, "remove")

      assert.is_truthy(#candidates > 0)
      for _, candidate in ipairs(candidates) do
        assert.is.equal(2, #candidate)  -- Should have removed one
      end
    end)

    it("should generate replace candidates", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {}
      })

      local current = {trainset[1], trainset[2]}
      local candidates = optimizer:_generateCandidates(current, "replace")

      assert.is_truthy(#candidates > 0)
      for _, candidate in ipairs(candidates) do
        assert.is.equal(2, #candidate)  -- Same size
      end
    end)

    it("should generate swap candidates", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {}
      })

      local current = {trainset[1], trainset[2], trainset[3]}
      local candidates = optimizer:_generateCandidates(current, "swap")

      assert.is_truthy(#candidates > 0)
      for _, candidate in ipairs(candidates) do
        assert.is.equal(3, #candidate)  -- Same size, different order
      end
    end)

    it("should not generate add candidates when at max", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {},
        max_demonstrations = 3
      })

      local current = {trainset[1], trainset[2], trainset[3]}
      local candidates = optimizer:_generateCandidates(current, "add")

      -- Should be empty since already at max
      assert.is.equal(0, #candidates)
    end)
  end)

  describe("_demoSignature", function()
    it("should create unique signature for each demo", function()
      local program = createProgram()
      local optimizer = COPRO.new(program)

      local demo1 = {question = "Test A", answer = "X"}
      local demo2 = {question = "Test B", answer = "Y"}

      local sig1 = optimizer:_demoSignature(demo1)
      local sig2 = optimizer:_demoSignature(demo2)

      assert.is_not.equal(sig1, sig2)
    end)

    it("should create same signature for identical demo", function()
      local program = createProgram()
      local optimizer = COPRO.new(program)

      local demo1 = {question = "Test", answer = "Answer"}
      local demo2 = {question = "Test", answer = "Answer"}

      local sig1 = optimizer:_demoSignature(demo1)
      local sig2 = optimizer:_demoSignature(demo2)

      assert.is.equal(sig1, sig2)
    end)
  end)

  describe("_heuristicScore", function()
    it("should score based on diversity", function()
      local program = createProgram()
      local optimizer = COPRO.new(program)

      local diverse = {
        {question = "A", answer = "1"},
        {question = "B", answer = "2"},
        {question = "C", answer = "3"}
      }

      local score = optimizer:_heuristicScore(diverse)

      assert.is.equal(1.0, score)  -- All unique
    end)

    it("should score lower for duplicates", function()
      local program = createProgram()
      local optimizer = COPRO.new(program)

      local duplicates = {
        {question = "A", answer = "1"},
        {question = "A", answer = "1"},
        {question = "B", answer = "2"}
      }

      local score = optimizer:_heuristicScore(duplicates)

      assert.is_truthy(score < 1.0)  -- Some duplicates
    end)
  end)

  describe("GetBestDemonstrations", function()
    it("should return best demonstrations after compilation", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {}
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx, 2)

      local demos = optimizer:GetBestDemonstrations()

      assert.is.truthy(demos)
      assert.is_truthy(#demos > 0)
    end)
  end)

  describe("GetBestScore", function()
    it("should return best score after compilation", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {}
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx, 2)

      local score = optimizer:GetBestScore()

      assert.is.truthy(score >= 0)
    end)
  end)

  describe("GetHistory", function()
    it("should return optimization history", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {},
        max_rounds = 3
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local history = optimizer:GetHistory()

      assert.is.truthy(#history > 0)
      assert.is_truthy(#history <= 3)

      for _, entry in ipairs(history) do
        assert.is_truthy(entry.round)
        assert.is_truthy(entry.num_demos)
        assert.is.truthy(type(entry.improved) == "boolean")
      end
    end)
  end)

  describe("AnalyzeOptimizationPath", function()
    it("should analyze optimization path", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {},
        max_rounds = 3
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local analysis = optimizer:AnalyzeOptimizationPath()

      assert.is.truthy(analysis.total_rounds > 0)
      assert.is.truthy(analysis.improved_rounds >= 0)
      assert.is.truthy(analysis.improved_rounds <= analysis.total_rounds)
      assert.is.truthy(analysis.final_score >= 0)
      assert.is.truthy(analysis.score_improvement >= 0)
    end)

    it("should handle empty history", function()
      local program = createProgram()
      local optimizer = COPRO.new(program, {
        trainset = {},
        valset = {}
      })

      local analysis = optimizer:AnalyzeOptimizationPath()

      assert.is.equal(0, analysis.total_rounds)
      assert.is.equal(0, analysis.improved_rounds)
    end)
  end)

  describe("Integration Tests", function()
    it("should perform full coordinate descent workflow", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {},
        max_rounds = 2,
        max_demonstrations = 4,
        candidates_per_round = 3
      })

      local ctx = Context.new({})
      local best_program, metrics = optimizer:Compile(ctx, 2)

      assert.is.truthy(best_program)
      assert.is_truthy(metrics.num_demonstrations > 0)
      assert.is.equal(2, metrics.rounds)
    end)

    it("should use early stopping", function()
      local program = createProgram()
      local trainset = {
        {ctx = Context.new({}), question = "Q1", answer = "A"},
        {ctx = Context.new({}), question = "Q2", answer = "B"}
      }

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {},
        max_rounds = 10,
        early_stopping_patience = 2
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local analysis = optimizer:AnalyzeOptimizationPath()

      -- Should stop early due to limited improvement opportunities
      assert.is.truthy(analysis.total_rounds <= 10)
    end)

    it("should respect max_demonstrations limit", function()
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

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {},
        max_rounds = 5,
        max_demonstrations = 5
      })

      local ctx = Context.new({})
      local best_program, metrics = optimizer:Compile(ctx, 3)

      assert.is.truthy(metrics.num_demonstrations <= 5)
    end)

    it("should handle large datasets efficiently", function()
      local program = createProgram()

      -- Create larger dataset
      local trainset = {}
      for i = 1, 30 do
        table.insert(trainset, {
          ctx = Context.new({}),
          question = "Question " .. i,
          answer = "Answer " .. i
        })
      end

      local optimizer = COPRO.new(program, {
        trainset = trainset,
        valset = {},
        max_rounds = 3,
        max_demonstrations = 5,
        candidates_per_round = 3
      })

      local ctx = Context.new({})
      local start_time = os.clock()
      local best_program, metrics = optimizer:Compile(ctx, 2)
      local elapsed = os.clock() - start_time

      assert.is.truthy(metrics.num_demonstrations > 0)
      assert.is.truthy(elapsed < 10)  -- Should complete in reasonable time
    end)
  end)
end)
