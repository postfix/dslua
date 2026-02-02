-- dslua/structured/validator.lua
-- JSON Schema Draft 7 subset validator (LLM-safe)

local M = {}

-- =============================================================================
-- Custom Validator Registry
-- =============================================================================

M.custom_validators = {}

function M.register(keyword, validator_fn)
  M.custom_validators[keyword] = validator_fn
end

-- =============================================================================
-- Main Validation Function
-- =============================================================================

function M.validate(data, schema)
  local errors = {}

  -- Validate root type
  if schema.type then
    local ok, err = M._validate_type(data, schema, "")
    if not ok then
      table.insert(errors, err)
      return {ok = false, errors = errors}
    end
  end

  -- Validate enum constraint
  if schema.enum then
    local ok, err = M._validate_enum(data, schema, "")
    if not ok then
      table.insert(errors, err)
      return {ok = false, errors = errors}
    end
  end

  -- Validate const constraint
  if schema.const then
    local ok, err = M._validate_const(data, schema, "")
    if not ok then
      table.insert(errors, err)
      return {ok = false, errors = errors}
    end
  end

  -- Validate composition keywords
  if schema.oneOf then
    local ok, err = M._validate_oneOf(data, schema, "")
    if not ok then
      table.insert(errors, err)
      return {ok = false, errors = errors}
    end
  end

  if schema.allOf then
    local ok, err = M._validate_allOf(data, schema, "")
    if not ok then
      table.insert(errors, err)
      return {ok = false, errors = errors}
    end
  end

  if schema.anyOf then
    local ok, err = M._validate_anyOf(data, schema, "")
    if not ok then
      table.insert(errors, err)
      return {ok = false, errors = errors}
    end
  end

  -- Check custom validators
  for keyword, validator_fn in pairs(M.custom_validators) do
    if schema[keyword] then
      local ok, err = validator_fn(data, schema)
      if not ok then
        table.insert(errors, err)
      end
    end
  end

  if #errors > 0 then
    return {ok = false, errors = errors}
  end

  return {ok = true, errors = {}}
end

-- =============================================================================
-- Type Validation
-- =============================================================================

function M._validate_type(data, schema, path)
  local expected_type = schema.type
  local actual_type = type(data)

  -- Map Lua types to JSON types
  if expected_type == "integer" then
    if actual_type ~= "number" then
      return false, {
        path = path .. "/type",
        keyword = "type",
        expected = "integer",
        actual = actual_type
      }
    end
    -- Check if it's a whole number
    if data ~= math.floor(data) then
      return false, {
        path = path .. "/type",
        keyword = "type",
        expected = "integer",
        actual = "number with fractional part"
      }
    end
    return true
  end

  -- Type mapping
  local type_map = {
    ["string"] = "string",
    ["number"] = "number",
    ["boolean"] = "boolean",
    ["null"] = "nil",
    ["object"] = "table",
    ["array"] = "table"
  }

  local expected_lua = type_map[expected_type]
  if not expected_lua then
    return false, {
      path = path .. "/type",
      keyword = "type",
      expected = expected_type,
      actual = "unknown type"
    }
  end

  if actual_type ~= expected_lua then
    return false, {
      path = path .. "/type",
      keyword = "type",
      expected = expected_type,
      actual = actual_type
    }
  end

  -- For objects, check it's not an array
  if expected_type == "object" and actual_type == "table" then
    if M._is_array(data) then
      return false, {
        path = path .. "/type",
        keyword = "type",
        expected = "object",
        actual = "array"
      }
    end
  end

  -- For arrays, check it's actually an array
  if expected_type == "array" and actual_type == "table" then
    if not M._is_array(data) then
      return false, {
        path = path .. "/type",
        keyword = "type",
        expected = "array",
        actual = "object"
      }
    end
  end

  -- If type is valid, validate constraints
  if expected_type == "string" then
    return M._validate_string_constraints(data, schema, path)
  elseif expected_type == "number" or expected_type == "integer" then
    return M._validate_numeric_constraints(data, schema, path)
  elseif expected_type == "object" then
    return M._validate_object_constraints(data, schema, path)
  elseif expected_type == "array" then
    return M._validate_array_constraints(data, schema, path)
  end

  return true
end

-- =============================================================================
-- String Constraint Validation
-- =============================================================================

function M._validate_string_constraints(data, schema, path)
  if schema.minLength and #data < schema.minLength then
    return false, {
      path = path .. "/minLength",
      keyword = "minLength",
      expected = "length >= " .. schema.minLength,
      actual = "length = " .. #data
    }
  end

  if schema.maxLength and #data > schema.maxLength then
    return false, {
      path = path .. "/maxLength",
      keyword = "maxLength",
      expected = "length <= " .. schema.maxLength,
      actual = "length = " .. #data
    }
  end

  if schema.pattern then
    -- Lua pattern matching
    if not string.match(data, "^" .. schema.pattern .. "$") then
      return false, {
        path = path .. "/pattern",
        keyword = "pattern",
        expected = "pattern: " .. schema.pattern,
        actual = "did not match pattern"
      }
    end
  end

  return true
end

-- =============================================================================
-- Numeric Constraint Validation
-- =============================================================================

function M._validate_numeric_constraints(data, schema, path)
  if schema.minimum ~= nil then
    if data < schema.minimum then
      return false, {
        path = path .. "/minimum",
        keyword = "minimum",
        expected = ">= " .. schema.minimum,
        actual = tostring(data)
      }
    end
  end

  if schema.maximum ~= nil then
    if data > schema.maximum then
      return false, {
        path = path .. "/maximum",
        keyword = "maximum",
        expected = "<= " .. schema.maximum,
        actual = tostring(data)
      }
    end
  end

  if schema.exclusiveMinimum and data <= schema.minimum then
    return false, {
      path = path .. "/minimum",
      keyword = "exclusiveMinimum",
      expected = "> " .. schema.minimum,
      actual = tostring(data)
    }
  end

  if schema.exclusiveMaximum and data >= schema.maximum then
    return false, {
      path = path .. "/maximum",
      keyword = "exclusiveMaximum",
      expected = "< " .. schema.maximum,
      actual = tostring(data)
    }
  end

  return true
end

-- =============================================================================
-- Object Constraint Validation
-- =============================================================================

function M._validate_object_constraints(data, schema, path)
  -- Validate required fields
  if schema.required then
    for _, field in ipairs(schema.required) do
      if data[field] == nil then
        return false, {
          path = path .. "/" .. field,
          keyword = "required",
          expected = "present",
          actual = "missing"
        }
      end
    end
  end

  -- Validate properties
  if schema.properties then
    for field_name, field_schema in pairs(schema.properties) do
      local field_value = data[field_name]

      -- Skip missing optional fields
      if field_value ~= nil then
        local field_path = path .. "/" .. field_name
        local ok, err = M._validate_type(field_value, field_schema, field_path)
        if not ok then
          return false, err
        end
      end
    end

    -- Check for additional properties
    if schema.additionalProperties == false then
      for field_name in pairs(data) do
        if not schema.properties[field_name] then
          return false, {
            path = path .. "/additionalProperties",
            keyword = "additionalProperties",
            expected = "only defined properties",
            actual = "found unexpected property: " .. field_name
          }
        end
      end
    end
  end

  -- Validate min/max properties
  if schema.minProperties then
    local count = 0
    for _ in pairs(data) do
      count = count + 1
    end
    if count < schema.minProperties then
      return false, {
        path = path .. "/minProperties",
        keyword = "minProperties",
        expected = ">= " .. schema.minProperties,
        actual = tostring(count)
      }
    end
  end

  if schema.maxProperties then
    local count = 0
    for _ in pairs(data) do
      count = count + 1
    end
    if count > schema.maxProperties then
      return false, {
        path = path .. "/maxProperties",
        keyword = "maxProperties",
        expected = "<= " .. schema.maxProperties,
        actual = tostring(count)
      }
    end
  end

  return true
end

-- =============================================================================
-- Array Constraint Validation
-- =============================================================================

function M._validate_array_constraints(data, schema, path)
  -- Validate items
  if schema.items then
    for i, item in ipairs(data) do
      local item_path = path .. "/" .. (i - 1)  -- 0-indexed in JSON Pointer
      local ok, err = M._validate_type(item, schema.items, item_path)
      if not ok then
        return false, err
      end
    end
  end

  -- Validate min/max items
  if schema.minItems and #data < schema.minItems then
    return false, {
      path = path .. "/minItems",
      keyword = "minItems",
      expected = "length >= " .. schema.minItems,
      actual = tostring(#data)
    }
  end

  if schema.maxItems and #data > schema.maxItems then
    return false, {
      path = path .. "/maxItems",
      keyword = "maxItems",
      expected = "length <= " .. schema.maxItems,
      actual = tostring(#data)
    }
  end

  -- Validate unique items (if implemented)
  if schema.uniqueItems then
    local seen = {}
    for i, item in ipairs(data) do
      -- For simple types, use value as key
      local key = type(item) == "table" and tostring(i) or item
      if seen[key] then
        return false, {
          path = path .. "/uniqueItems",
          keyword = "uniqueItems",
          expected = "all unique",
          actual = "duplicate found"
        }
      end
      seen[key] = true
    end
  end

  return true
end

-- =============================================================================
-- Enum and Const Validation
-- =============================================================================

function M._validate_enum(data, schema, path)
  for _, value in ipairs(schema.enum) do
    if data == value then
      return true
    end
  end

  return false, {
    path = path .. "/enum",
    keyword = "enum",
    expected = "one of: " .. table.concat(schema.enum, ", "),
    actual = tostring(data)
  }
end

function M._validate_const(data, schema, path)
  if data ~= schema.const then
    return false, {
      path = path .. "/const",
      keyword = "const",
      expected = tostring(schema.const),
      actual = tostring(data)
    }
  end
  return true
end

-- =============================================================================
-- Composition Validation
-- =============================================================================

function M._validate_oneOf(data, schema, path)
  local match_count = 0

  for _, sub_schema in ipairs(schema.oneOf) do
    local result = M.validate(data, sub_schema)
    if result.ok then
      match_count = match_count + 1
    end
  end

  if match_count == 0 then
    return false, {
      path = path .. "/oneOf",
      keyword = "oneOf",
      expected = "exactly one schema matches",
      actual = "none matched"
    }
  end

  if match_count > 1 then
    return false, {
      path = path .. "/oneOf",
      keyword = "oneOf",
      expected = "exactly one schema matches",
      actual = match_count .. " matched"
    }
  end

  return true
end

function M._validate_allOf(data, schema, path)
  for i, sub_schema in ipairs(schema.allOf) do
    -- If sub_schema has no type, infer from data type
    local schema_to_validate = sub_schema
    if not sub_schema.type then
      schema_to_validate = M._copy_table(sub_schema)
      schema_to_validate.type = type(data)
      -- Map Lua types to JSON types
      if schema_to_validate.type == "nil" then
        schema_to_validate.type = "null"
      elseif schema_to_validate.type == "table" then
        schema_to_validate.type = M._is_array(data) and "array" or "object"
      end
    end

    local result = M.validate(data, schema_to_validate)
    if not result.ok then
      return false, {
        path = path .. "/allOf/" .. (i - 1),
        keyword = "allOf",
        expected = "all schemas must match",
        actual = "schema " .. i .. " failed"
      }
    end
  end

  return true
end

-- Helper function to deep copy a table
function M._copy_table(tbl)
  local copy = {}
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      copy[k] = M._copy_table(v)
    else
      copy[k] = v
    end
  end
  return copy
end

function M._validate_anyOf(data, schema, path)
  local match_count = 0

  for _, sub_schema in ipairs(schema.anyOf) do
    local result = M.validate(data, sub_schema)
    if result.ok then
      match_count = match_count + 1
    end
  end

  if match_count == 0 then
    return false, {
      path = path .. "/anyOf",
      keyword = "anyOf",
      expected = "at least one schema matches",
      actual = "none matched"
    }
  end

  return true
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

function M._is_array(tbl)
  -- Check if table is an array (consecutive integer keys starting at 1)
  local i = 1
  for key, value in pairs(tbl) do
    if key ~= i then
      return false
    end
    i = i + 1
  end
  return i > 1
end

return M
