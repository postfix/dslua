-- specs/optimizers/mipro_prompt_tuner_spec.lua
-- Tests for MIPRO PromptTuner Module

local PromptTuner = require("dslua.optimizers.mipro_prompt_tuner")
local FewShot = require("dslua.modules.fewshot")
local Signature = require("dslua.core.signature")
local Field = require("dslua.core.field")

describe("MIPRO PromptTuner Module", function()

  describe("OptimizePrompt", function()

    it("should create FewShot program with selected demos", function()
      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("answer")}
      )
      local module = {
        Signature = function()
          return signature
        end
      }

      local trainset = {
        {input = {question = "2+2"}, output = {answer = "4"}},
        {input = {question = "3+3"}, output = {answer = "6"}},
        {input = {question = "5+5"}, output = {answer = "10"}}
      }

      local hyperparams = {
        num_demos = 2,
        demo_selection = "random"
      }

      local program = PromptTuner.OptimizePrompt(module, hyperparams, trainset)

      assert.is_not_nil(program)
      -- Program should be a FewShot module
    end)

    it("should select diverse demonstrations when strategy is diverse", function()
      local trainset = {
        {input = {question = "2+2"}, output = {answer = "4"}},
        {input = {question = "2*3"}, output = {answer = "6"}},
        {input = {question = "10/2"}, output = {answer = "5"}},
        {input = {question = "20-5"}, output = {answer = "15"}},
        {input = {question = "3*4"}, output = {answer = "12"}}
      }

      local selected = PromptTuner._selectDemos(trainset, 3, "diverse")

      assert.is_equal(3, #selected)
      -- Should select 3 different demos
    end)

    it("should select random demonstrations when strategy is random", function()
      local trainset = {
        {input = {question = "Q1"}, output = {answer = "A1"}},
        {input = {question = "Q2"}, output = {answer = "A2"}},
        {input = {question = "Q3"}, output = {answer = "A3"}}
      }

      local selected = PromptTuner._selectDemos(trainset, 2, "random", {seed = 42})

      assert.is_equal(2, #selected)
    end)

  end)

  describe("_generateInstruction", function()

    it("should return nil for none template", function()
      local instruction = PromptTuner._generateInstruction({instruction_template = "none"})
      assert.is_nil(instruction)
    end)

    it("should return basic instruction for basic template", function()
      local instruction = PromptTuner._generateInstruction({instruction_template = "basic"})
      assert.is_not_nil(instruction)
      assert.is_true(type(instruction) == "string")
    end)

    it("should return detailed instruction for detailed template", function()
      local instruction = PromptTuner._generateInstruction({instruction_template = "detailed"})
      assert.is_not_nil(instruction)
      assert.is_true(type(instruction) == "string")
    end)

    it("should return cot instruction for cot template", function()
      local instruction = PromptTuner._generateInstruction({instruction_template = "cot"})
      assert.is_not_nil(instruction)
      assert.is_true(type(instruction) == "string")
      assert.is_true(string.find(instruction:lower(), "step") ~= nil)
    end)

  end)

  describe("Private Functions", function()
    describe("_randomSubset", function()
      it("should select k random demos", function()
        local trainset = {
          {input = {question = "Q1"}, output = {answer = "A1"}},
          {input = {question = "Q2"}, output = {answer = "A2"}},
          {input = {question = "Q3"}, output = {answer = "A3"}}
        }

        local selected = PromptTuner._randomSubset(trainset, 2, {})

        assert.is.equal(2, #selected)
      end)

      it("should use seed for reproducibility", function()
        local trainset = {
          {input = {question = "Q1"}, output = {answer = "A1"}},
          {input = {question = "Q2"}, output = {answer = "A2"}},
          {input = {question = "Q3"}, output = {answer = "A3"}}
        }

        local selected1 = PromptTuner._randomSubset(trainset, 2, {seed = 42})
        local selected2 = PromptTuner._randomSubset(trainset, 2, {seed = 42})

        assert.is.equal(#selected1, #selected2)
      end)

      it("should limit k to trainset size", function()
        local trainset = {
          {input = {question = "Q1"}, output = {answer = "A1"}},
          {input = {question = "Q2"}, output = {answer = "A2"}}
        }

        local selected = PromptTuner._randomSubset(trainset, 5, {})

        assert.is.equal(2, #selected)
      end)
    end)

    describe("_diverseSubset", function()
      it("should select diverse demos", function()
        local trainset = {
          {input = {question = "short"}, output = {answer = "A1"}},
          {input = {question = "medium length question"}, output = {answer = "A2"}},
          {input = {question = "very long question with many words"}, output = {answer = "A3"}}
        }

        local selected = PromptTuner._diverseSubset(trainset, 2, {})

        assert.is.equal(2, #selected)
      end)
    end)

    describe("_similarSubset", function()
      it("should select similar demos", function()
        local trainset = {
          {input = {question = "Q1 with similar length"}, output = {answer = "A1"}},
          {input = {question = "Q2 with similar length"}, output = {answer = "A2"}},
          {input = {question = "tiny"}, output = {answer = "A3"}}
        }

        local selected = PromptTuner._similarSubset(trainset, 2, {})

        assert.is.equal(2, #selected)
      end)
    end)

    describe("_computeDiversity", function()
      it("should return 1.0 when no demos selected", function()
        local example = {input = {question = "test"}}
        local diversity = PromptTuner._computeDiversity(example, {})

        assert.is.equal(1.0, diversity)
      end)

      it("should compute higher diversity for dissimilar examples", function()
        local example = {input = {question = "very long question here"}}
        local selected = {
          {input = {question = "x"}}
        }

        local diversity = PromptTuner._computeDiversity(example, selected)

        assert.is.truthy(diversity > 0)
      end)
    end)

    describe("_computeSimilarity", function()
      it("should return 0.0 when no demos selected", function()
        local example = {input = {question = "test"}}
        local similarity = PromptTuner._computeSimilarity(example, {})

        assert.is.equal(0.0, similarity)
      end)

      it("should compute similarity to selected demos", function()
        local example = {input = {question = "similar length question"}}
        local selected = {
          {input = {question = "similar length question"}}
        }

        local similarity = PromptTuner._computeSimilarity(example, selected)

        assert.is.truthy(similarity >= 0 and similarity <= 1)
      end)
    end)

    describe("_computeExampleSimilarity", function()
      it("should return 1.0 for identical length inputs", function()
        local ex1 = {input = {question = "test"}}
        local ex2 = {input = {question = "test"}}

        local sim = PromptTuner._computeExampleSimilarity(ex1, ex2)

        assert.is.equal(1.0, sim)
      end)

      it("should return 1.0 for empty inputs", function()
        local ex1 = {input = {}}
        local ex2 = {input = {}}

        local sim = PromptTuner._computeExampleSimilarity(ex1, ex2)

        assert.is.equal(1.0, sim)
      end)

      it("should compute lower similarity for different length inputs", function()
        local ex1 = {input = {question = "short"}}
        local ex2 = {input = {question = "very long question with many words"}}

        local sim = PromptTuner._computeExampleSimilarity(ex1, ex2)

        assert.is.truthy(sim < 1.0)
      end)
    end)
  end)

end)
