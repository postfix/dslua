-- dslua/modules/structured_predict.lua
-- StructuredPredict module - convenience façade combining Predict + StructuredOutput

local Predict = require("dslua.modules.predict")
local StructuredOutput = require("dslua.structured.decorator")
local Schema = require("dslua.structured.schema")
local Signature = require("dslua.core.signature")
local Field = require("dslua.core.field")

local M = {}

-- =============================================================================
-- PredictWithMetadata - Predict that exposes prompt/llm_opts for retries
-- =============================================================================

local PredictWithMetadata = {}
PredictWithMetadata.__index = PredictWithMetadata

function PredictWithMetadata.new(signature)
  local self = Predict.new(signature)
  self._decorator = nil  -- Will hold the StructuredOutput decorator
  setmetatable(self, PredictWithMetadata)
  return self
end

-- Inherit from Predict
setmetatable(PredictWithMetadata, {__index = Predict})

function PredictWithMetadata:Process(ctx, input)
  local llm = ctx:LLM() or self:LLM()
  if not llm then
    error("No LLM configured in module or context")
  end

  local prompt = self:_buildPrompt(input)
  local llm_opts = {}  -- Could be made configurable via opts

  local response = llm:Complete(ctx, prompt, llm_opts)

  -- Expose metadata for safe retries
  response.prompt = prompt
  response.llm_opts = llm_opts

  return response
end

-- =============================================================================
-- StructuredPredict Constructor
-- =============================================================================

function M.new(schema, opts)
  opts = opts or {}

  -- Infer schema from signature if not provided
  if not schema then
    schema = M._infer_schema_from_signature(opts.signature)
  end

  -- Create default signature if not provided
  local signature = opts.signature or Signature.new({}, {})

  -- Create PredictWithMetadata module
  local base = PredictWithMetadata.new(signature)

  -- Wrap with StructuredOutput decorator
  local structured = StructuredOutput.new(base, schema, opts)

  -- Store decorator reference for method forwarding
  base._decorator = structured

  -- Make structured respond to Signature() calls
  structured.Signature = function()
    return signature
  end

  -- Make structured respond to WithLLM() calls
  structured.WithLLM = function(self, llm)
    -- Set LLM on base Predict module (Base module has _llm field)
    base._llm = llm
    return self
  end

  return structured
end

-- =============================================================================
-- Schema Inference from Signature
-- =============================================================================

function M._infer_schema_from_signature(signature)
  if not signature then
    error("Signature is required when schema is not provided")
  end

  local output_fields = signature:OutputFields()
  if not output_fields or #output_fields == 0 then
    error("Signature must have OutputFields to infer schema")
  end

  -- Build schema from output fields
  local properties = {}

  for _, field in ipairs(output_fields) do
    -- Field objects don't have Type(), default to string
    local field_name = field:Name()

    properties[field_name] = {
      type = "string"  -- Default type since we can't infer from Field
    }
  end

  -- All output fields are required
  local required = {}
  for _, field in ipairs(output_fields) do
    table.insert(required, field:Name())
  end

  return Schema.Object(properties, {
    required = required
  })
end

return M
