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

  describe("Timeout handling", function()
    it("should return timeout error when deadline exceeded", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "{\"age\":30}",
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {})

      -- Set deadline in the past
      local past_deadline = os.time() * 1000 - 1000  -- 1 second ago
      local mock_ctx = {
        LLM = function() return {} end,
        deadline_ms = past_deadline
      }

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_false(envelope.success)
      assert.is_equal(Types.ErrorCodes.TIMEOUT, envelope.error.code)
      assert.is_equal("process", envelope.error.stage)
      assert.is_false(envelope.error.recoverable)
    end)

    it("should not timeout when deadline not exceeded", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "{\"age\":30}",
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {})

      -- Set deadline in the future
      local future_deadline = os.time() * 1000 + 60000  -- 1 minute from now
      local mock_ctx = {
        LLM = function() return {} end,
        deadline_ms = future_deadline
      }

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(envelope.success)
      assert.is_equal(30, envelope.data.age)
    end)

    it("should handle nil deadline_ms gracefully", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "{\"age\":30}",
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {})

      local mock_ctx = {
        LLM = function() return {} end,
        deadline_ms = nil  -- No deadline set
      }

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(envelope.success)
      assert.is_equal(30, envelope.data.age)
    end)
  end)

  describe("Provenance tracking details", function()
    it("should set provenance.source to strict for valid JSON", function()
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

      local decorated = StructuredOutput.new(mock_module, schema, {})

      local mock_ctx = {LLM = function() return {} end}

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(envelope.success)
      assert.is_equal("strict", envelope.provenance.source)
      assert.is_equal(0, envelope.provenance.attempt_count)
      assert.is_equal(0, #envelope.provenance.repair_operations)
    end)

    it("should set provenance.source to repaired when repairs applied", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "```json\n{\"age\":30,}\n```",  -- Needs repair
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
      assert.is_equal("repaired", envelope.provenance.source)
      assert.is_true(#envelope.provenance.repair_operations > 0)
    end)

    it("should set provenance.source to retried after successful retry", function()
      local attempt = 0

      local mock_module = {
        Process = function(self, ctx, input)
          attempt = attempt + 1
          return {
            content = attempt == 1 and "{\"age\":\"thirty\"}" or "{\"age\":30}",
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
        return {content = "{\"age\":30}"}
      end

      local mock_ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(envelope.success)
      assert.is_equal("retried", envelope.provenance.source)
      assert.is_true(envelope.provenance.attempt_count >= 1)
    end)

    it("should track repair_operations list", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "```json\n{\"name\":\"Alice\",}\n```",
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({name = {type = "string"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        enable_repair = true,
        repair_markdown_fences = true,
        repair_trailing_commas = true
      })

      local mock_ctx = {LLM = function() return {} end}

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(envelope.success)
      assert.is_not_nil(envelope.provenance.repair_operations)
      assert.is_true(#envelope.provenance.repair_operations > 0)
    end)

    it("should have empty repair_operations for strict mode", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "{\"name\":\"Alice\"}",
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({name = {type = "string"}})

      local decorated = StructuredOutput.new(mock_module, schema, {})

      local mock_ctx = {LLM = function() return {} end}

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(envelope.success)
      assert.is_equal("strict", envelope.provenance.source)
      assert.is_equal(0, #envelope.provenance.repair_operations)
    end)
  end)

  describe("Retry prompt format", function()
    it("should include error details in retry prompt", function()
      local retry_prompts = {}

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
        table.insert(retry_prompts, prompt)
        return {content = "{\"age\":30}"}
      end

      local mock_ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(envelope.success)
      assert.is_true(#retry_prompts >= 1)

      local retry_prompt = retry_prompts[1]
      assert.is_true(string.find(retry_prompt, "ERROR DETAILS") ~= nil,
        "Prompt should have ERROR DETAILS section")
      assert.is_true(string.find(retry_prompt, "Validation failed") ~= nil,
        "Prompt should mention validation failure")
    end)

    it("should include schema in retry prompt", function()
      local retry_prompts = {}

      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "invalid",
            prompt = "Generate user",
            llm_opts = {temperature = 0.7}
          }
        end
      }

      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_retries = 1
      })

      local mock_llm = {}
      function mock_llm:Complete(ctx, prompt, opts)
        table.insert(retry_prompts, prompt)
        return {content = "{\"name\":\"Alice\",\"age\":30}"}
      end

      local mock_ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(#retry_prompts >= 1)

      local retry_prompt = retry_prompts[1]
      assert.is_true(string.find(retry_prompt, "%[SCHEMA%]") ~= nil,
        "Prompt should have SCHEMA section")
      assert.is_true(string.find(retry_prompt, "type") ~= nil or
                     string.find(retry_prompt, "properties") ~= nil,
        "Prompt should include schema content")
    end)

    it("should format validation errors correctly", function()
      local retry_prompts = {}

      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "{\"age\":\"thirty\"}",  -- Type error
            prompt = "Generate user",
            llm_opts = {temperature = 0.7}
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_retries = 1
      })

      local mock_llm = {}
      function mock_llm:Complete(ctx, prompt, opts)
        table.insert(retry_prompts, prompt)
        return {content = "{\"age\":30}"}
      end

      local mock_ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(#retry_prompts >= 1)

      local retry_prompt = retry_prompts[1]
      assert.is_true(string.find(retry_prompt, "Path:") ~= nil,
        "Should include error path")
      assert.is_true(string.find(retry_prompt, "Expected:") ~= nil,
        "Should include expected type")
      assert.is_true(string.find(retry_prompt, "Got:") ~= nil,
        "Should include actual type")
      assert.is_true(string.find(retry_prompt, "Error:") ~= nil,
        "Should include error keyword")
    end)

    it("should include parse error details when JSON parse fails", function()
      local retry_prompts = {}

      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "not json at all",
            prompt = "Generate user",
            llm_opts = {temperature = 0.7}
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_retries = 1
      })

      local mock_llm = {}
      function mock_llm:Complete(ctx, prompt, opts)
        table.insert(retry_prompts, prompt)
        return {content = "{\"age\":30}"}
      end

      local mock_ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_true(#retry_prompts >= 1)

      local retry_prompt = retry_prompts[1]
      assert.is_true(string.find(retry_prompt, "parse") ~= nil,
        "Should mention parse stage")
    end)
  end)

  describe("Error context structure", function()
    it("should truncate last_raw_output in error context", function()
      local long_content = string.rep("x", 1000)

      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = long_content,
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({name = {type = "string"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_error_output_chars = 200
      })

      local mock_ctx = {LLM = function() return {} end}

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_false(envelope.success)
      assert.is_not_nil(envelope.error.last_raw_output)
      assert.is_true(#envelope.error.last_raw_output <= 200)
    end)

    it("should track retry_count accurately", function()
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
        max_retries = 2
      })

      local mock_llm = {}
      function mock_llm:Complete(ctx, prompt, opts)
        return {content = "still invalid"}
      end

      local mock_ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_false(envelope.success)
      assert.is_not_nil(envelope.error.retry_count)
      assert.is_equal(2, envelope.error.retry_count)
    end)

    it("should include validation errors in diagnostics", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "{\"age\":\"thirty\"}",  -- Type error
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_retries = 0
      })

      local mock_ctx = {LLM = function() return {} end}

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_false(envelope.success)
      assert.is_equal(Types.ErrorCodes.SCHEMA_VALIDATION, envelope.error.code)
      assert.is_not_nil(envelope.error.validation_errors)
      assert.is_true(#envelope.error.validation_errors > 0)

      local first_error = envelope.error.validation_errors[1]
      assert.is_not_nil(first_error.path)
      assert.is_not_nil(first_error.keyword)
      assert.is_not_nil(first_error.expected)
      assert.is_not_nil(first_error.actual)
    end)

    it("should include parse_error in diagnostics when JSON parse fails", function()
      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "invalid json {",
            prompt = "Generate user"
          }
        end
      }

      local schema = Schema.Object({age = {type = "integer"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_retries = 0
      })

      local mock_ctx = {LLM = function() return {} end}

      local envelope = decorated:Process(mock_ctx, {})

      assert.is_false(envelope.success)
      assert.is_equal(Types.ErrorCodes.JSON_PARSE, envelope.error.code)
      assert.is_not_nil(envelope.error.parse_error)
    end)
  end)
end)
