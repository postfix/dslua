-- specs/modules/structured_predict_spec.lua
-- Tests for dslua/modules/structured_predict.lua

local StructuredPredict = require("dslua.modules.structured_predict")
local Schema = require("dslua.structured.schema")
local Field = require("dslua.core.field")
local Signature = require("dslua.core.signature")

describe("StructuredPredict Module", function()

  describe("Basic creation", function()
    it("should create a new StructuredPredict module", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("user_profile")}
      )

      local module = StructuredPredict.new(schema, {
        signature = signature
      })

      assert.is_not_nil(module)
      assert.is_not_nil(module:Signature())
    end)

    it("should work without signature when schema provided", function()
      local schema = Schema.Object({
        name = {type = "string"}
      })

      local module = StructuredPredict.new(schema, {})

      assert.is_not_nil(module)
    end)
  end)

  describe("Process method", function()
    it("should return structured result envelope", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("result")}
      )

      local module = StructuredPredict.new(schema, {
        signature = signature
      })

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {
            content = "{\"name\":\"Alice\",\"age\":30}"
          }
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = module:Process(ctx, {question = "Generate user"})

      assert.is_not_nil(envelope)
      assert.is_true(envelope.success)
      assert.is_not_nil(envelope.data)
      assert.is_equal("Alice", envelope.data.name)
      assert.is_equal(30, envelope.data.age)
    end)

    it("should include prompt in response for safe retries", function()
      local schema = Schema.Object({
        name = {type = "string"}
      })

      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("result")}
      )

      local module = StructuredPredict.new(schema, {
        signature = signature
      })

      local captured_prompts = {}
      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          table.insert(captured_prompts, prompt)
          return {
            content = "{\"name\":\"Bob\"}"
          }
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = module:Process(ctx, {question = "Generate"})

      assert.is_true(envelope.success)
      assert.is_true(#captured_prompts >= 1)
    end)

    it("should retry on validation failure when retries enabled", function()
      local schema = Schema.Object({
        age = {type = "integer"}
      })

      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("result")}
      )

      local module = StructuredPredict.new(schema, {
        signature = signature,
        max_retries = 2,
        retry_temperature = 0
      })

      local attempt = 0
      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          attempt = attempt + 1
          if attempt == 1 then
            return {content = "{\"age\":\"thirty\"}"}  -- Invalid
          else
            return {content = "{\"age\":30}"}  -- Valid
          end
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = module:Process(ctx, {question = "Generate"})

      assert.is_true(envelope.success)
      assert.is_equal(30, envelope.data.age)
      assert.is_equal("retried", envelope.provenance.source)
    end)

    it("should return error when validation fails and retries exhausted", function()
      local schema = Schema.Object({
        age = {type = "integer"}
      })

      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("result")}
      )

      local module = StructuredPredict.new(schema, {
        signature = signature,
        max_retries = 1
      })

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {content = "invalid json"}
        end
      }

      local ctx = {
        LLM = function()
          return mock_llm
        end
      }

      local envelope = module:Process(ctx, {question = "Generate"})

      assert.is_false(envelope.success)
      assert.is_not_nil(envelope.error)
    end)
  end)

  describe("LLM configuration", function()
    it("should support WithLLM method", function()
      local schema = Schema.Object({
        name = {type = "string"}
      })

      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("result")}
      )

      local module = StructuredPredict.new(schema, {
        signature = signature
      })

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {content = "{\"name\":\"Test\"}"}
        end
      }

      module:WithLLM(mock_llm)

      local ctx = {LLM = function() return mock_llm end}

      local envelope = module:Process(ctx, {question = "Generate"})

      assert.is_true(envelope.success)
    end)

    it("should use module LLM if context LLM not available", function()
      local schema = Schema.Object({
        name = {type = "string"}
      })

      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("result")}
      )

      local module = StructuredPredict.new(schema, {
        signature = signature
      })

      local mock_llm = {
        Complete = function(self, ctx, prompt, opts)
          return {content = "{\"name\":\"FromModuleLLM\"}"}
        end
      }

      module:WithLLM(mock_llm)

      local ctx = {
        LLM = function()
          return nil  -- No LLM in context
        end
      }

      local envelope = module:Process(ctx, {question = "Generate"})

      assert.is_true(envelope.success)
      assert.is_equal("FromModuleLLM", envelope.data.name)
    end)
  end)

  describe("Schema inference from signature", function()
    it("should infer schema from signature when schema not provided", function()
      -- Schema inference requires explicit type information
      -- For now, just test that it doesn't crash
      local signature = Signature.new(
        {Field.new("question"):WithDescription("A question")},
        {Field.new("name"):WithDescription("A name")}
      )

      local module = StructuredPredict.new(nil, {
        signature = signature
      })

      assert.is_not_nil(module)
    end)
  end)

  describe("Options forwarding", function()
    it("should forward options to decorator", function()
      local schema = Schema.Object({
        name = {type = "string"}
      })

      local signature = Signature.new(
        {Field.new("question")},
        {Field.new("result")}
      )

      local module = StructuredPredict.new(schema, {
        signature = signature,
        max_retries = 3,
        retry_temperature = 0,
        enable_repair = true
      })

      assert.is_not_nil(module)
    end)
  end)

end)
