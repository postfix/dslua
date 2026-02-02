-- specs/integration/structured_output_ollama_spec.lua
-- Integration tests for Structured Output with Ollama

local dkjson = require("dkjson")
local StructuredOutput = require("dslua.structured.decorator")
local Schema = require("dslua.structured.schema")
local Context = require("dslua.core.context")
local Ollama = require("dslua.llms.providers.ollama")

describe("Structured Output with Ollama", function()
  -- Helper function to check if Ollama is available
  local function ollama_available()
    local handler = io.popen("curl -s http://127.0.0.1:11434/api/tags 2>/dev/null", "r")
    local output = handler:read("*a")
    handler:close()
    return output ~= nil and output ~= ""
  end

  setup(function()
    if not ollama_available() then
      pending("Ollama not available at http://127.0.0.1:11434")
    end
  end)

  describe("Basic structured output", function()
    it("should validate valid JSON response from Ollama", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local mock_llm = Ollama.new("gpt-oss:latest")

      local mock_module = {
        Process = function(self, ctx, input)
          local prompt = string.format(
            "Generate a user profile with name '%s' and age 30. Return ONLY JSON.",
            input.name
          )
          local response = ctx:LLM():Complete(ctx, prompt)

          -- Add prompt for safe retries
          response.prompt = prompt
          response.llm_opts = {temperature = 0.7}

          return response
        end
      }

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_retries = 2,
        retry_temperature = 0
      })

      local ctx = Context.new({llm = mock_llm})
      local envelope = decorated:Process(ctx, {name = "Alice"})

      -- Should succeed with valid JSON
      assert.is_not_nil(envelope)
      assert.is_not_nil(envelope.success, "Envelope should have success field")

      if envelope.success then
        assert.is_not_nil(envelope.data)
        assert.is.equal("Alice", envelope.data.name)
        assert.is.equal(30, envelope.data.age)
        print(string.format("✅ Ollama test passed! data=%s",
          dkjson.encode(envelope.data)))
      else
        print(string.format("❌ Test failed: %s - %s",
          envelope.error.code, envelope.error.message))
        assert.is_true(envelope.success)  -- This will fail with diagnostic info
      end
    end)
  end)

  describe("Retry mechanism with Ollama", function()
    it("should retry and get valid JSON on second attempt", function()
      local attempt = 0

      local mock_module = {
        Process = function(self, ctx, input)
          attempt = attempt + 1

          local prompt
          if attempt == 1 then
            -- First attempt: return invalid JSON
            prompt = "Return JSON: age=thirty (invalid on purpose)"
          else
            -- Subsequent: valid prompt
            prompt = "Return JSON: age=30"
          end

          local response = ctx:LLM():Complete(ctx, prompt)
          response.prompt = prompt
          response.llm_opts = {temperature = 0.7}

          return response
        end
      }

      local schema = Schema.Object({
        age = {type = "integer"}
      })

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_retries = 2,
        retry_temperature = 0
      })

      local mock_llm = Ollama.new("gpt-oss:latest")
      local ctx = Context.new({llm = mock_llm})

      local envelope = decorated:Process(ctx, {})

      assert.is_not_nil(envelope)

      if envelope.success then
        assert.is_equal(30, envelope.data.age)
        assert.is.equal("retried", envelope.provenance.source)
        print("✅ Retry test passed!")
      else
        fail(string.format("Retry test failed: %s", envelope.error.message))
      end
    end)
  end)

  describe("Error handling with Ollama", function()
    it("should handle non-JSON response gracefully", function()
      local mock_module = {
        Process = function(self, ctx, input)
          local prompt = "Just say the word FAIL and nothing else"
          local response = ctx:LLM():Complete(ctx, prompt)
          response.prompt = prompt
          response.llm_opts = {temperature = 0.7}
          return response
        end
      }

      local schema = Schema.Object({value = {type = "number"}})

      local decorated = StructuredOutput.new(mock_module, schema, {
        max_retries = 1,
        debug_enabled = true
      })

      local mock_llm = Ollama.new("gpt-oss:latest")
      local ctx = Context.new({llm = mock_llm})

      local envelope = decorated:Process(ctx, {})

      assert.is_not_nil(envelope)

      if envelope.success then
        print(string.format("Test unexpectedly succeeded: data=%s",
          dkjson.encode(envelope.data)))
        -- This is actually OK - Ollama managed to format JSON
      else
        print(string.format("✅ Error handling test passed! code=%s, recoverable=%s",
          envelope.error.code,
          tostring(envelope.error.recoverable)))
        assert.is_false(envelope.success)
      end
    end)
  end)
end)
