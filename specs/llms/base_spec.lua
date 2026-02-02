-- specs/llms/base_spec.lua
-- Tests for dslua/llms/base.lua

describe("BaseLLM", function()
  local BaseLLM = require("dslua.llms.base")

  describe("new", function()
    it("should create BaseLLM with config", function()
      local llm = BaseLLM.new({
        api_key = "test-key",
        model = "test-model"
      })

      assert.is_truthy(llm)
    end)

    it("should handle empty config", function()
      local llm = BaseLLM.new({})

      assert.is_truthy(llm)
    end)

    it("should store config values", function()
      local llm = BaseLLM.new({
        api_key = "secret-key",
        model = "gpt-4",
        base_url = "https://api.example.com"
      })

      assert.is_truthy(llm)
    end)
  end)

  describe("APIKey", function()
    it("should return API key", function()
      local llm = BaseLLM.new({
        api_key = "test-key"
      })

      assert.is.equal("test-key", llm:APIKey())
    end)

    it("should return nil for unset API key", function()
      local llm = BaseLLM.new({})

      assert.is_falsy(llm:APIKey())
    end)
  end)

  describe("Model", function()
    it("should return model name", function()
      local llm = BaseLLM.new({
        model = "test-model"
      })

      assert.is.equal("test-model", llm:Model())
    end)

    it("should return nil for unset model", function()
      local llm = BaseLLM.new({})

      assert.is_falsy(llm:Model())
    end)
  end)

  describe("BaseURL", function()
    it("should return base URL", function()
      local llm = BaseLLM.new({
        base_url = "https://api.example.com"
      })

      assert.is.equal("https://api.example.com", llm:BaseURL())
    end)

    it("should return nil for unset base URL", function()
      local llm = BaseLLM.new({})

      assert.is_falsy(llm:BaseURL())
    end)
  end)

  describe("Complete", function()
    it("should be implemented by subclasses", function()
      -- Complete is abstract and should be overridden
      local llm = BaseLLM.new({})

      assert.has_error(function()
        llm:Complete(nil, {}, {})
      end)
    end)
  end)
end)
