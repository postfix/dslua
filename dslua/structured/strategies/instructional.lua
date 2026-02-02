-- dslua/structured/strategies/instructional.lua
-- Instructional strategy - adds format instructions to guide LLM JSON output

local M = {}

local dkjson = require("dkjson")

-- =============================================================================
-- Main API
-- =============================================================================

function M.generate(schema, opts)
  opts = opts or {}

  if schema.type ~= "object" or not schema.properties then
    return M._generic_instructions()
  end

  -- Build instructions for each property
  local lines = {}

  table.insert(lines, "[OUTPUT FORMAT]")
  table.insert(lines, "Return JSON with the following structure:")
  table.insert(lines, "")

  -- Process each property
  for prop_name, prop_schema in pairs(schema.properties) do
    local instruction = M._generate_field_instruction(prop_name, prop_schema, schema)
    table.insert(lines, instruction)
  end

  -- Add required fields note
  if schema.required and #schema.required > 0 then
    table.insert(lines, "")
    table.insert(lines, "Required fields: " .. table.concat(schema.required, ", "))
  end

  table.insert(lines, "")
  table.insert(lines, "[END FORMAT]")

  return table.concat(lines, "\n")
end

-- =============================================================================
-- Field Instruction Generation
-- =============================================================================

function M._generate_field_instruction(field_name, field_schema, parent_schema)
  local type_name = field_schema.type
  local is_required = parent_schema.required and
                      M._table_contains(parent_schema.required, field_name)

  -- Build instruction line
  local parts = {}
  local required_marker = is_required and "*" or ""

  table.insert(parts, string.format("%s%s:", required_marker, field_name))

  -- Add type/constraint info
  local constraint_info = M._get_constraint_info(field_schema, type_name)
  table.insert(parts, constraint_info)

  return table.concat(parts, " ")
end

function M._get_constraint_info(schema, type_name)
  -- Handle const
  if schema.const then
    return dkjson.encode(schema.const)
  end

  -- Handle each type
  if type_name == "string" then
    return M._get_string_constraint_info(schema)
  elseif type_name == "number" or type_name == "integer" then
    return M._get_numeric_constraint_info(schema, type_name)
  elseif type_name == "boolean" then
    return "true | false"
  elseif type_name == "null" then
    return "null"
  elseif type_name == "array" then
    return M._get_array_constraint_info(schema)
  elseif type_name == "object" then
    return M._get_object_constraint_info(schema)
  end

  return "?"
end

-- =============================================================================
-- String Constraints
-- =============================================================================

function M._get_string_constraint_info(schema)
  local parts = {}

  -- Use placeholder value instead of type name
  table.insert(parts, '"<string>"')

  if schema.enum then
    table.insert(parts, string.format("enum: %s", table.concat(schema.enum, "|")))
  end

  if schema.minLength then
    table.insert(parts, string.format("min_len=%d", schema.minLength))
  end

  if schema.maxLength then
    table.insert(parts, string.format("max_len=%d", schema.maxLength))
  end

  if schema.pattern then
    table.insert(parts, "pattern")
  end

  return table.concat(parts, ", ")
end

-- =============================================================================
-- Numeric Constraints
-- =============================================================================

function M._get_numeric_constraint_info(schema, type_name)
  local parts = {}

  -- Use placeholder value
  local placeholder = type_name == "integer" and "42" or "123.45"
  table.insert(parts, placeholder)

  if schema.minimum then
    local op = schema.exclusiveMinimum and ">" or ">="
    table.insert(parts, string.format("%s %s", op, schema.minimum))
  end

  if schema.maximum then
    local op = schema.exclusiveMaximum and "<" or "<="
    table.insert(parts, string.format("%s %s", op, schema.maximum))
  end

  return table.concat(parts, ", ")
end

-- =============================================================================
-- Array Constraints
-- =============================================================================

function M._get_array_constraint_info(schema)
  local parts = {}

  if schema.minItems then
    table.insert(parts, string.format("minItems=%d", schema.minItems))
  end

  if schema.maxItems then
    table.insert(parts, string.format("maxItems=%d", schema.maxItems))
  end

  -- Get item type info
  local items_schema = schema.items or {type = "string"}
  local item_info = M._get_constraint_info(items_schema, items_schema.type)

  -- Build array with placeholder items
  local array_def
  if items_schema.type == "string" then
    array_def = '["<string>", ...]'
  elseif items_schema.type == "number" or items_schema.type == "integer" then
    array_def = "[123, ...]"
  elseif items_schema.type == "boolean" then
    array_def = "[true, ...]"
  elseif items_schema.type == "object" then
    array_def = "[{...}, ...]"
  else
    array_def = "[...]"
  end

  if #parts > 0 then
    return string.format("%s (%s)", array_def, table.concat(parts, ", "))
  else
    return array_def
  end
end

-- =============================================================================
-- Object Constraints
-- =============================================================================

function M._get_object_constraint_info(schema)
  if not schema.properties then
    return '{"<key>": "<value>"}'
  end

  -- For nested objects, show placeholder structure
  local props = {}
  for prop_name, prop_schema in pairs(schema.properties) do
    local prop_placeholder = M._get_placeholder_for_type(prop_schema.type)
    table.insert(props, string.format('"%s": %s', prop_name, prop_placeholder))
  end

  return string.format("{%s}", table.concat(props, ", "))
end

function M._get_placeholder_for_type(type_name)
  if type_name == "string" then
    return '"<string>"'
  elseif type_name == "number" then
    return "123"
  elseif type_name == "integer" then
    return "42"
  elseif type_name == "boolean" then
    return "true"
  elseif type_name == "null" then
    return "null"
  elseif type_name == "array" then
    return '[...]'
  elseif type_name == "object" then
    return '{...}'
  else
    return '"?"'
  end
end

-- =============================================================================
-- Generic Instructions
-- =============================================================================

function M._generic_instructions()
  return [[
[OUTPUT FORMAT]
Return valid JSON following the schema requirements above.
[END FORMAT]
]]
end

-- =============================================================================
-- Utilities
-- =============================================================================

function M._table_contains(tbl, value)
  for _, v in ipairs(tbl) do
    if v == value then
      return true
    end
  end
  return false
end

return M
