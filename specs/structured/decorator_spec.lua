-- specs/structured/decorator_spec.lua
-- Tests for dslua/structured/decorator.lua

local StructuredOutput = require("dslua.structured.decorator")
local Schema = require("dslua.structured.schema")
local Types = require("dslua.structured.types")

describe("StructuredOutput Decorator", function()

  describe("Basic wrapping", function()
    it("should wrap a module successfully", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "{\"name\":\"Alice\",\"age\":30}",
            prompt = "Generate a user profile"
          }
        end
      }

      local user_schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local decorated = StructuredOutput.new(mock_module, user_schema, {})
      assert.is_not_nil(decorated)
    end)
  end)

  describe("Structured mode (default)", function()
    it("should validate valid JSON response", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "{\"name\":\"Alice\",\"age\":30}",
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local decorated = StructuredOutput.new(mock_module, schema, {
        mode = "structured"
      })

      local mock_ctx = {
        LLM = function()
          return {
            Complete = function(self, ctx, prompt, opts)
              return {content = "{\"name\":\"Alice\",\"age\":30}"}
            end
          }
        end
      }

      local envelope = decorated:Process(mock_ctx, {question = "Generate user"})

      assert.is_true(envelope.success)
      assert.is_not_nil(envelope.data)
      assert.is.equal("Alice", envelope.data.name)
      assert.is.equal(30, envelope.data.age)
      assert.is.equal("strict", envelope.provenance.source)
    end)

    it("should return error for invalid JSON", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "not valid json",
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({name = {type = "string"}})

      local decorated = StructuredOutput.new(mock_module, schema, {})

      local mock_ctx = {LLM = function() return {} end}

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_false(envelope.success)
      assert.is_equal(Types.ErrorCodes.JSON_PARSE, envelope.error.code)
    end)

    it("should return error for schema validation failure", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "{\"age\":\"thirty\"}",  -- String, not number
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({
        age = {type = "integer"}
      })

      local decorated = StructuredOutput.new(mock_module, schema, {})

      local mock_ctx = {LLM = function() return {} end}

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_false(envelope.success)
      assert.is_equal(Types.ErrorCodes.SCHEMA_VALIDATION, envelope.error.code)
    end)
  end)

  describe("Retry mechanism", function()
    it("should retry on validation failure", function()
      local attempt_count = 0

      local mock_module = {
        Process = function(self, ctx, input)
          attempt_count = attempt_count + 1
          return {
            content = attempt_count == 1 and "{\"age\":\"thirty\"}" or "{\"age\":30}",
            prompt = "Generate user",
            llm_opts = {temperature = 0.7}
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_retries = 2,
        retry_temperature = 0
      })

      local mock_llm = {}
      function mock_llm:Complete(ctx, prompt, opts)
        -- On retry, return corrected JSON
        return {content = "{\"age\":30}"}
      end

      local mock_ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(envelope.success)
      assert.is.equal("retried", envelope.provenance.source)
      assert.is_true(envelope.provenance.attempt_count >= 1)
    end)

    it("should use low temperature on retries", function()
      local retry_opts_captured = {}

      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "invalid json",
            prompt = "Generate user",
            llm_opts = {temperature = 0.7}
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_retries = 1,
        retry_temperature = 0
      })

      local mock_llm = {}
      function mock_llm:Complete(ctx, prompt, opts)
        table.insert(retry_opts_captured, opts)
        return {content = "{\"age\":30}"}
      end

      local mock_ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = decorated:Process(mock_ctx, {})

      -- Should capture retry opts with low temperature
      assert.is_true(#retry_opts_captured >= 1)
      if #retry_opts_captured >= 1 then
        assert.is_equal(0, retry_opts_captured[1].temperature)
      end
    end)

    it("should fail after max retries exhausted", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "invalid json",
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_retries = 1
      })

      local mock_llm = {}
      function mock_llm:Complete(ctx, prompt, opts)
        -- Always return invalid JSON
        return {content = "still invalid"}
      end

      local mock_ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_false(envelope.success)
      assert.is_equal(Types.ErrorCodes.MAX_RETRIES, envelope.error.code)
    end)
  end)

  describe("Repair mechanism", function()
    it("should apply safe repairs when enabled", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "```json\n{\"age\":30,}\n```",  -- Markdown fence + trailing comma
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        enable_repair = true,
        repair_markdown_fences = true,
        repair_trailing_commas = true
      })

      local mock_ctx = {LLM = function() return {} end}

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(envelope.success)
      assert.is.equal("repaired", envelope.provenance.source)
      assert.is_true(#envelope.provenance.repair_operations > 0)
    end)
  end)

  describe("Error handling", function()
    it("should return ERR_RETRY_UNSUPPORTED when prompt missing", function()
      local mock_module = {
        Process = function(self, ctx, input)
          -- No prompt field exposed
          return {
            content = "{\"age\":\"thirty\"}"  -- Invalid JSON - type mismatch
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_retries = 2  -- Wants retries
      })

      local mock_ctx = {LLM = function() return {} end}

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_false(envelope.success)
      assert.is_equal(Types.ErrorCodes.RETRY_UNSUPPORTED, envelope.error.code)
      assert.is_false(envelope.error.recoverable)
    end)
  end)

  describe("Debug mode", function()
    it("should include debug info when enabled", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "{\"age\":30}",
            prompt = "Generate user",
            llm_opts = {temperature = 0.7}
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        debug_enabled = true,
        include_raw_response = true
      })

      local mock_ctx = {LLM = function() return {} end}

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(envelope.success)
      assert.is_not_nil(envelope.debug)
      assert.is_not_nil(envelope.debug.raw_response)
    end)

    it("should not include debug info when disabled", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "{\"age\":30}",
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        debug_enabled = false
      })

      local mock_ctx = {LLM = function() return {} end}

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(envelope.success)
      assert.is_nil(envelope.debug)
    end)
  end)
end)
