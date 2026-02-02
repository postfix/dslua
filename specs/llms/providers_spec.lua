-- specs/llms/providers_spec.lua
-- Tests for LLM provider modules

describe("LLM Providers", function()
  local Anthropic = require("dslua.llms.providers.anthropic")
  local Gemini = require("dslua.llms.providers.gemini")
  local Ollama = require("dslua.llms.providers.ollama")
  local OpenAI = require("dslua.llms.providers.openai")

  describe("Anthropic Provider", function()
    it("should create Anthropic provider", function()
      local provider = Anthropic.new("test-key", "claude-3")

      assert.is_truthy(provider)
    end)

    it("should accept custom options", function()
      local provider = Anthropic.new("test-key", "claude-3", {
        temperature = 0.7,
        max_tokens = 2000
      })

      assert.is_truthy(provider)
    end)

    it("should handle nil model", function()
      local provider = Anthropic.new("test-key", nil)

      assert.is_truthy(provider)
    end)
  end)

  describe("Gemini Provider", function()
    it("should create Gemini provider", function()
      local provider = Gemini.new("test-key", "gemini-pro")

      assert.is_truthy(provider)
    end)

    it("should accept custom options", function()
      local provider = Gemini.new("test-key", "gemini-pro", {
        temperature = 0.5
      })

      assert.is_truthy(provider)
    end)
  end)

  describe("Ollama Provider", function()
    it("should create Ollama provider", function()
      local provider = Ollama.new("llama2")

      assert.is_truthy(provider)
    end)

    it("should accept custom options", function()
      local provider = Ollama.new("llama2", {
        base_url = "http://localhost:11434",
        timeout = 30000
      })

      assert.is_truthy(provider)
    end)
  end)

  describe("OpenAI Provider", function()
    it("should create OpenAI provider", function()
      local provider = OpenAI.new("test-key", "gpt-4")

      assert.is_truthy(provider)
    end)

    it("should accept custom options", function()
      local provider = OpenAI.new("test-key", "gpt-4", {
        temperature = 0.5,
        max_tokens = 1000
      })

      assert.is_truthy(provider)
    end)
  end)
end)
