-- specs/optimizers/simba_spec.lua
-- Tests for SIMBA Optimizer

describe("SIMBA Optimizer", function()
  local SIMBA = require("dslua.optimizers.simba")
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
    it("should create SIMBA optimizer with program", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = SIMBA.new(program, {
        trainset = trainset,
        valset = {}
      })

      assert.is.equal(program, optimizer._module)
      assert.is.equal(0.7, optimizer._similarity_threshold)
      assert.is.equal(0.1, optimizer._diversity_bonus)
      assert.is.equal(8, optimizer._max_demonstrations)
    end)

    it("should accept custom options", function()
      local program = createProgram()
      local optimizer = SIMBA.new(program, {
        similarity_threshold = 0.8,
        diversity_bonus = 0.2,
        max_demonstrations = 5,
        temperature = 0.5,
        max_refinements = 3
      })

      assert.is.equal(0.8, optimizer._similarity_threshold)
      assert.is.equal(0.2, optimizer._diversity_bonus)
      assert.is.equal(5, optimizer._max_demonstrations)
      assert.is.equal(0.5, optimizer._temperature)
      assert.is.equal(3, optimizer._max_refinements)
    end)
  end)

  describe("Compile", function()
    it("should compile with trainset", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = SIMBA.new(program, {
        trainset = trainset,
        valset = {},
        max_demonstrations = 3
      })

      local ctx = Context.new({})

      local best_program, metrics = optimizer:Compile(ctx, 5)

      assert.is.truthy(best_program)
      assert.is.truthy(metrics.num_demos)
      assert.is.truthy(metrics.num_demos <= 3)
      assert.is.equal(metrics.num_demos, #optimizer._selected_demos)
    end)

    it("should handle empty trainset", function()
      local program = createProgram()
      local optimizer = SIMBA.new(program, {
        trainset = {},
        valset = {}
      })

      local ctx = Context.new({})

      local best_program, metrics = optimizer:Compile(ctx)

      assert.is.truthy(best_program)
      assert.is.equal(0, metrics.num_demos)
    end)

    it("should handle single example trainset", function()
      local program = createProgram()
      local trainset = {
        {ctx = Context.new({}), question = "Single", answer = "Answer"}
      }

      local optimizer = SIMBA.new(program, {
        trainset = trainset,
        valset = {}
      })

      local ctx = Context.new({})

      local best_program, metrics = optimizer:Compile(ctx)

      assert.is.truthy(best_program)
      assert.is.equal(1, metrics.num_demos)
    end)

    it("should select diverse demonstrations", function()
      local program = createProgram()
      local trainset = {
        {ctx = Context.new({}), question = "Math problem 1", answer = "A"},
        {ctx = Context.new({}), question = "Math problem 2", answer = "B"},
        {ctx = Context.new({}), question = "History question", answer = "C"},
        {ctx = Context.new({}), question = "Science fact", answer = "D"}
      }

      local optimizer = SIMBA.new(program, {
        trainset = trainset,
        valset = {},
        max_demonstrations = 4,
        diversity_bonus = 0.3
      })

      local ctx = Context.new({})

      local best_program, metrics = optimizer:Compile(ctx, 5)

      -- Should have selected diverse examples
      assert.is.truthy(metrics.num_demos > 0)
      assert.is.truthy(metrics.num_demos <= 4)
    end)
  end)

  describe("_similarity", function()
    it("should calculate similarity for similar examples", function()
      local program = createProgram()
      local optimizer = SIMBA.new(program)

      local ex1 = {question = "What is the capital of France?", answer = "Paris"}
      local ex2 = {question = "What is the capital of Germany?", answer = "Berlin"}

      local sim = optimizer:_similarity(ex1, ex2)

      -- Should have some similarity due to shared words
      assert.is.truthy(sim > 0)
    end)

    it("should calculate similarity for different examples", function()
      local program = createProgram()
      local optimizer = SIMBA.new(program)

      local ex1 = {question = "Mathematics problem", answer = "42"}
      local ex2 = {question = "History question", answer = "World War II"}

      local sim = optimizer:_similarity(ex1, ex2)

      -- Should have low similarity
      assert.is.truthy(sim >= 0 and sim < 1)
    end)

    it("should handle examples with no common words", function()
      local program = createProgram()
      local optimizer = SIMBA.new(program)

      local ex1 = {question = "ABC", answer = "XYZ"}
      local ex2 = {question = "DEF", answer = "QRS"}

      local sim = optimizer:_similarity(ex1, ex2)

      assert.is.equal(0, sim)
    end)

    it("should calculate similarity for examples with same answer", function()
      local program = createProgram()
      local optimizer = SIMBA.new(program)

      local ex1 = {question = "First question", answer = "Same answer"}
      local ex2 = {question = "Second question", answer = "Same answer"}

      local sim = optimizer:_similarity(ex1, ex2)

      -- Should have high similarity due to same answer
      assert.is.truthy(sim > 0.5)
    end)
  end)

  describe("_tokenize", function()
    it("should tokenize simple text", function()
      local program = createProgram()
      local optimizer = SIMBA.new(program)

      local tokens = optimizer:_tokenize("hello world")

      assert.is.truthy(tokens["hello"])
      assert.is.truthy(tokens["world"])
      assert.is.falsy(tokens["test"])
    end)

    it("should handle punctuation", function()
      local program = createProgram()
      local optimizer = SIMBA.new(program)

      local tokens = optimizer:_tokenize("Hello, world!")

      assert.is.truthy(tokens["Hello"])
      assert.is.truthy(tokens["world"])
    end)

    it("should handle empty string", function()
      local program = createProgram()
      local optimizer = SIMBA.new(program)

      local tokens = optimizer:_tokenize("")

      local count = 0
      for _ in pairs(tokens) do count = count + 1 end

      assert.is.equal(0, count)
    end)

    it("should handle repeated words", function()
      local program = createProgram()
      local optimizer = SIMBA.new(program)

      local tokens = optimizer:_tokenize("test test test")

      assert.is.truthy(tokens["test"])
    end)
  end)

  describe("_selectDiverseDemos", function()
    it("should select diverse demonstrations", function()
      local program = createProgram()
      local optimizer = SIMBA.new(program, {
        max_demonstrations = 3
      })

      local dataset = {
        {question = "Math 1", answer = "A"},
        {question = "Math 2", answer = "B"},
        {question = "History", answer = "C"},
        {question = "Science", answer = "D"}
      }

      local similarities = optimizer:_calculateSimilarities(dataset)
      local selected = optimizer:_selectDiverseDemos(dataset, similarities)

      assert.is.truthy(#selected > 0)
      assert.is.truthy(#selected <= 3)
    end)

    it("should handle dataset smaller than max_demonstrations", function()
      local program = createProgram()
      local optimizer = SIMBA.new(program, {
        max_demonstrations = 10
      })

      local dataset = {
        {question = "A", answer = "1"},
        {question = "B", answer = "2"}
      }

      local similarities = optimizer:_calculateSimilarities(dataset)
      local selected = optimizer:_selectDiverseDemos(dataset, similarities)

      assert.is.equal(2, #selected)
    end)
  end)

  describe("GetSimilarityMatrix", function()
    it("should return similarity scores after compilation", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = SIMBA.new(program, {
        trainset = trainset,
        valset = {}
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local matrix = optimizer:GetSimilarityMatrix()

      assert.is.truthy(matrix)
    end)
  end)

  describe("GetSelectedDemos", function()
    it("should return selected demonstrations after compilation", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = SIMBA.new(program, {
        trainset = trainset,
        valset = {}
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local demos = optimizer:GetSelectedDemos()

      assert.is.truthy(demos)
      assert.is.truthy(#demos > 0)
    end)
  end)

  describe("GetBestScore", function()
    it("should return best score after compilation", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = SIMBA.new(program, {
        trainset = trainset,
        valset = {}
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local score = optimizer:GetBestScore()

      assert.is.truthy(score >= 0)
    end)
  end)

  describe("AnalyzeDiversity", function()
    it("should analyze diversity of selected demos", function()
      local program = createProgram()
      local trainset = createTrainset()

      local optimizer = SIMBA.new(program, {
        trainset = trainset,
        valset = {}
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local analysis = optimizer:AnalyzeDiversity()

      assert.is.truthy(analysis.avg_similarity >= 0 and analysis.avg_similarity <= 1)
      assert.is.truthy(analysis.min_similarity >= 0 and analysis.min_similarity <= 1)
      assert.is.truthy(analysis.max_similarity >= 0 and analysis.max_similarity <= 1)
    end)

    it("should handle single selected demo", function()
      local program = createProgram()
      local trainset = {
        {ctx = Context.new({}), question = "Single", answer = "Answer"}
      }

      local optimizer = SIMBA.new(program, {
        trainset = trainset,
        valset = {}
      })

      local ctx = Context.new({})
      optimizer:Compile(ctx)

      local analysis = optimizer:AnalyzeDiversity()

      assert.is.equal(1.0, analysis.avg_similarity)
    end)
  end)

  describe("Integration Tests", function()
    it("should work with simple optimization workflow", function()
      local program = createProgram()
      local trainset = {
        {ctx = Context.new({}), question = "Add 2+2", answer = "4"},
        {ctx = Context.new({}), question = "Add 3+3", answer = "6"},
        {ctx = Context.new({}), question = "Multiply 5*5", answer = "25"},
        {ctx = Context.new({}), question = "Divide 10/2", answer = "5"}
      }

      local optimizer = SIMBA.new(program, {
        trainset = trainset,
        valset = {},
        max_demonstrations = 3,
        diversity_bonus = 0.2
      })

      local ctx = Context.new({})
      local best_program, metrics = optimizer:Compile(ctx, 5)

      assert.is.truthy(best_program)
      assert.is.truthy(metrics.num_demos > 0)
      assert.is.truthy(metrics.num_demos <= 3)
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

      local optimizer = SIMBA.new(program, {
        trainset = trainset,
        valset = {},
        max_demonstrations = 5
      })

      local ctx = Context.new({})
      local start_time = os.clock()
      local best_program, metrics = optimizer:Compile(ctx, 3)
      local elapsed = os.clock() - start_time

      assert.is.truthy(metrics.num_demos > 0)
      assert.is.truthy(elapsed < 10)  -- Should complete in reasonable time
    end)
  end)
end)
