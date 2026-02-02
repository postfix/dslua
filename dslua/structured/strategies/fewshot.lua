-- dslua/structured/strategies/fewshot.lua
-- Few-shot strategy - adds examples to prompts to help LLMs learn JSON structure

local M = {}

local dkjson = require("dkjson")

-- =============================================================================
-- Constants
-- =============================================================================

M.Placeholders = {
  string = '"<string>"',
  number = '123',
  integer = '42',
  boolean = 'true',
  null = 'null',
  array_empty = '[]',
  array_items = '["<string>", "<string>"]',
  object_empty = '{}',
  object_example = '{"key": "<value>"}'
}

-- =============================================================================
-- Main API
-- =============================================================================

function M.generate(schema, opts)
  opts = opts or {}
  local max_examples = opts.max_examples or 3

  if max_examples == 0 then
    return ""
  end

  -- Determine optimal number of examples based on schema complexity
  local example_count = M._calculate_example_count(schema, max_examples)

  -- Generate examples
  local examples = {}
  for i = 1, example_count do
    local example = M._generate_example(schema, i)
    table.insert(examples, example)
  end

  -- Format as prompt addition
  return M._format_examples(examples)
end

-- =============================================================================
-- Example Generation
-- =============================================================================

function M._calculate_example_count(schema, max_examples)
  -- Simple heuristic: more complex schemas get more examples
  local complexity = M._calculate_complexity(schema)

  if complexity <= 2 then
    return math.min(1, max_examples)
  elseif complexity <= 5 then
    return math.min(2, max_examples)
  else
    return max_examples
  end
end

function M._calculate_complexity(schema)
  local count = 0

  if schema.type == "object" and schema.properties then
    for _ in pairs(schema.properties) do
      count = count + 1
    end
  elseif schema.type == "array" and schema.items then
    count = 1 + M._calculate_complexity(schema.items)
  end

  return count
end

function M._generate_example(schema, example_index)
  local example_value = M._generate_value(schema, example_index)
  return dkjson.encode(example_value, {indent = true})
end

function M._generate_value(schema, example_index)
  local schema_type = schema.type

  -- Handle enum: use actual enum values
  if schema.enum then
    local idx = (example_index - 1) % #schema.enum + 1
    return schema.enum[idx]
  end

  -- Handle const: use const value
  if schema.const then
    return schema.const
  end

  -- Handle null type
  if schema_type == "null" then
    return nil
  end

  -- Handle boolean type
  if schema_type == "boolean" then
    -- Alternate between true and false across examples
    return example_index % 2 == 1
  end

  -- Handle string type
  if schema_type == "string" then
    return M._generate_string_value(schema, example_index)
  end

  -- Handle number/integer types
  if schema_type == "number" or schema_type == "integer" then
    return M._generate_numeric_value(schema, example_index)
  end

  -- Handle array type
  if schema_type == "array" then
    return M._generate_array_value(schema, example_index)
  end

  -- Handle object type
  if schema_type == "object" then
    return M._generate_object_value(schema, example_index)
  end

  -- Fallback
  return nil
end

function M._generate_string_value(schema, example_index)
  -- If has pattern, try to generate something matching
  if schema.pattern then
    -- For patterns like email, generate example-like value
    if string.find(schema.pattern, "@") then
      return "user@example.com"
    elseif string.find(schema.pattern, "%d") then
      return "123"
    end
  end

  -- Check constraints
  if schema.minLength and schema.minLength > 0 then
    local len = math.max(schema.minLength, 5)
    return string.rep("x", len)
  end

  if schema.enum then
    local idx = (example_index - 1) % #schema.enum + 1
    return schema.enum[idx]
  end

  -- Default placeholder
  return "<string>"
end

function M._generate_numeric_value(schema, example_index)
  local base = example_index * 10

  -- Handle constraints
  if schema.minimum then
    base = math.max(base, schema.minimum)
    if schema.exclusiveMinimum then
      base = base + 1
    end
  end

  if schema.maximum then
    base = math.min(base, schema.maximum)
    if schema.exclusiveMaximum then
      base = base - 1
    end
  end

  -- For integers, ensure whole number
  if schema.type == "integer" then
    return math.floor(base)
  end

  -- Add fractional part for numbers
  return base + (example_index * 0.1)
end

function M._generate_array_value(schema, example_index)
  local items_schema = schema.items or {type = "string"}

  -- Determine array length based on constraints
  local length = 2
  if schema.minItems then
    length = math.max(length, schema.minItems)
  end
  if schema.maxItems then
    length = math.min(length, schema.maxItems)
  end

  -- Generate array items
  local items = {}
  for i = 1, length do
    local item_value = M._generate_value(items_schema, i)
    table.insert(items, item_value)
  end

  return items
end

function M._generate_object_value(schema, example_index)
  local result = {}

  if not schema.properties then
    return result
  end

  -- Generate values for each property
  for prop_name, prop_schema in pairs(schema.properties) do
    local prop_index = example_index
    -- Use string hash of property name to vary values
    local name_hash = 0
    for i = 1, #prop_name do
      name_hash = name_hash + string.byte(prop_name, i)
    end
    prop_index = prop_index + name_hash

    local value = M._generate_value(prop_schema, prop_index)
    result[prop_name] = value
  end

  return result
end

-- =============================================================================
-- Formatting
-- =============================================================================

function M._format_examples(examples)
  if #examples == 0 then
    return ""
  end

  local parts = {}

  table.insert(parts, "[EXAMPLES]")
  table.insert(parts, "Study these examples to understand the required JSON format:")
  table.insert(parts, "")

  for i, example in ipairs(examples) do
    table.insert(parts, string.format("Example %d:", i))
    table.insert(parts, example)
    table.insert(parts, "")
  end

  table.insert(parts, "[YOUR TASK]")
  table.insert(parts, "Generate JSON following the same structure as the examples above.")
  table.insert(parts, "")

  return table.concat(parts, "\n")
end

-- =============================================================================
-- Utilities
-- =============================================================================

function M.get_placeholder(type_name)
  return M.Placeholders[type_name] or '"<value>"'
end

return M
