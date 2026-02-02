-- specs/llms/init_spec.lua
-- Tests for dslua/llms/init.lua

describe("LLM Module", function()
  local LLM = require("dslua.llms")

  describe("OpenAI", function()
    it("should create OpenAI provider", function()
      local provider = LLM.OpenAI("test-key", "gpt-4")

      assert.is_truthy(provider)
    end)

    it("should accept custom options", function()
      local provider = LLM.OpenAI("test-key", "gpt-4", {
        temperature = 0.5,
        max_tokens = 1000
      })

      assert.is.truthy(provider)
    end)

    it("should handle nil model", function()
      local provider = LLM.OpenAI("test-key", nil)

      assert.is.truthy(provider)
    end)
  end)

  describe("Anthropic", function()
    it("should create Anthropic provider", function()
      local provider = LLM.Anthropic("test-key", "claude-3")

      assert.is_truthy(provider)
    end)

    it("should accept custom options", function()
      local provider = LLM.Anthropic("test-key", "claude-3", {
        temperature = 0.7,
        max_tokens = 2000
      })

      assert.is.truthy(provider)
    end)
  end)

  describe("Gemini", function()
    it("should create Gemini provider", function()
      local provider = LLM.Gemini("test-key", "gemini-pro")

      assert.is_truthy(provider)
    end)

    it("should accept custom options", function()
      local provider = LLM.Gemini("test-key", "gemini-pro", {
        temperature = 0.5
      })

      assert.is.truthy(provider)
    end)
  end)

  describe("Ollama", function()
    it("should create Ollama provider", function()
      local provider = LLM.Ollama("llama2")

      assert.is_truthy(provider)
    end)

    it("should accept custom options", function()
      local provider = LLM.Ollama("llama2", {
        host = "localhost:11434"
      })

      assert.is.truthy(provider)
    end)

    it("should handle nil model", function()
      local provider = LLM.Ollama(nil)

      assert.is.truthy(provider)
    end)
  end)
end)
