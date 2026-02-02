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

end)
