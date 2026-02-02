-- dslua/structured/schema.lua
-- JSON Schema Draft 7 Lua DSL and normalization

local M = {}

-- =============================================================================
-- Supported Keywords Registry (LLM-safe Draft 7 subset)
-- =============================================================================

M.SupportedKeywords = {
  -- Core types
  type = true,
  enum = true,
  const = true,

  -- Object keywords
  properties = true,
  required = true,
  additionalProperties = true,
  minProperties = true,
  maxProperties = true,

  -- Array keywords
  items = true,
  minItems = true,
  maxItems = true,
  uniqueItems = true,

  -- String keywords
  minLength = true,
  maxLength = true,
  pattern = true,

  -- Numeric keywords
  minimum = true,
  maximum = true,
  exclusiveMinimum = true,
  exclusiveMaximum = true,

  -- Composition keywords
  oneOf = true,
  allOf = true,
  anyOf = true,
}

-- =============================================================================
-- Primitive Type Builders
-- =============================================================================

function M.String(opts)
  opts = opts or {}
  return {
    type = "string",
    minLength = opts.minLength,
    maxLength = opts.maxLength,
    pattern = opts.pattern
  }
end

function M.Number(opts)
  opts = opts or {}
  return {
    type = "number",
    minimum = opts.minimum,
    maximum = opts.maximum,
    exclusiveMinimum = opts.exclusiveMinimum,
    exclusiveMaximum = opts.exclusiveMaximum
  }
end

function M.Integer(opts)
  opts = opts or {}
  return {
    type = "integer",
    minimum = opts.minimum,
    maximum = opts.maximum,
    exclusiveMinimum = opts.exclusiveMinimum,
    exclusiveMaximum = opts.exclusiveMaximum
  }
end

function M.Boolean()
  return {type = "boolean"}
end

function M.Null()
  return {type = "null"}
end

-- =============================================================================
-- Composite Type Builders
-- =============================================================================

function M.Object(properties, opts)
  opts = opts or {}
  local schema = {
    type = "object",
    properties = properties or {}
  }

  if opts.required then
    schema.required = opts.required
  end

  if opts.additionalProperties ~= nil then
    schema.additionalProperties = opts.additionalProperties
  else
    schema.additionalProperties = false  -- Default: strict
  end

  if opts.minProperties then
    schema.minProperties = opts.minProperties
  end

  if opts.maxProperties then
    schema.maxProperties = opts.maxProperties
  end

  return schema
end

function M.Array(items_schema, opts)
  opts = opts or {}
  local schema = {
    type = "array",
    items = items_schema
  }

  if opts.minItems then
    schema.minItems = opts.minItems
  end

  if opts.maxItems then
    schema.maxItems = opts.maxItems
  end

  if opts.uniqueItems then
    schema.uniqueItems = opts.uniqueItems
  end

  return schema
end

-- =============================================================================
-- Constraint Builders
-- =============================================================================

function M.Enum(values)
  return {enum = values}
end

function M.Const(value)
  return {const = value}
end

-- =============================================================================
-- Composition Builders
-- =============================================================================

function M.OneOf(schemas)
  return {oneOf = schemas}
end

function M.AllOf(schemas)
  return {allOf = schemas}
end

function M.AnyOf(schemas)
  return {anyOf = schemas}
end

-- =============================================================================
-- Schema Validation
-- =============================================================================

function M.Validate(schema)
  -- Check if type is present
  if not schema.type then
    return false, "Schema missing required field: type"
  end

  -- Validate type value
  local valid_types = {
    ["string"] = true,
    ["number"] = true,
    ["integer"] = true,
    ["boolean"] = true,
    ["object"] = true,
    ["array"] = true,
    ["null"] = true
  }

  if not valid_types[schema.type] then
    return false, "Invalid type: " .. tostring(schema.type)
  end

  -- Check for unknown keywords
  for key, _ in pairs(schema) do
    if key ~= "type" and not M.SupportedKeywords[key] then
      return false, "Unsupported keyword: " .. key
    end
  end

  -- Type-specific validation
  if schema.type == "object" then
    if not schema.properties then
      return false, "Object schema missing properties field"
    end
  elseif schema.type == "array" then
    if not schema.items then
      return false, "Array schema missing items field"
    end
  end

  return true, nil
end

-- =============================================================================
-- Schema Normalization
-- =============================================================================

function M.Normalize(lua_schema)
  -- Create a copy to avoid mutating original
  local normalized = {}

  -- Copy all fields
  for key, value in pairs(lua_schema) do
    normalized[key] = value
  end

  -- Set defaults
  if normalized.type == "object" then
    if normalized.additionalProperties == nil then
      normalized.additionalProperties = false
    end
  end

  return normalized
end

-- =============================================================================
-- JSON Schema Loading (for external .json files)
-- =============================================================================

function M.LoadJSON(filepath)
  local json = require("dkjson")
  local f, err = io.open(filepath, "r")

  if not f then
    return nil, "Failed to open file: " .. err
  end

  local content = f:read("*all")
  f:close()

  local data, pos, decode_err = json.decode(content, 1, nil)

  if not data then
    return nil, "Failed to parse JSON: " .. decode_err
  end

  -- Normalize the loaded schema
  return M.Normalize(data), nil
end

return M
