-- dslua/structured/strategy_selector.lua
-- Strategy selector - chooses appropriate template strategy based on schema

local M = {}

-- =============================================================================
-- Main API
-- =============================================================================

function M.select_strategy(schema, strategy_choice, opts)
  opts = opts or {}

  -- If strategy explicitly specified, use it
  if strategy_choice and strategy_choice ~= "auto" then
    return strategy_choice
  end

  -- Analyze schema characteristics
  local analysis = M.analyze_schema(schema)

  -- Apply decision table
  return M._apply_decision_table(analysis, opts)
end

function M.analyze_schema(schema)
  local analysis = {
    is_flat = true,
    has_nested_objects = false,
    has_arrays = false,
    has_enum = false,
    has_pattern = false,
    has_const = false,
    field_count = 0,
    max_depth = 0
  }

  if schema.type ~= "object" or not schema.properties then
    return analysis
  end

  -- Count fields and analyze structure
  for prop_name, prop_schema in pairs(schema.properties) do
    analysis.field_count = analysis.field_count + 1

    local depth = M._analyze_property(prop_schema, analysis, 1)
    analysis.max_depth = math.max(analysis.max_depth, depth)
  end

  -- Determine if flat (no nested structures, <= 5 fields)
  analysis.is_flat = (not analysis.has_nested_objects and
                      not analysis.has_arrays and
                      analysis.field_count <= 5)

  return analysis
end

-- =============================================================================
-- Property Analysis
-- =============================================================================

function M._analyze_property(prop_schema, analysis, depth)
  -- Check for constraints
  if prop_schema.enum then
    analysis.has_enum = true
  end

  if prop_schema.const then
    analysis.has_const = true
  end

  if prop_schema.pattern then
    analysis.has_pattern = true
  end

  -- Check type
  local prop_type = prop_schema.type

  if prop_type == "object" then
    analysis.has_nested_objects = true

    if prop_schema.properties then
      local max_child_depth = depth
      for _, child_schema in pairs(prop_schema.properties) do
        local child_depth = M._analyze_property(child_schema, analysis, depth + 1)
        max_child_depth = math.max(max_child_depth, child_depth)
      end
      return max_child_depth
    end
  elseif prop_type == "array" then
    analysis.has_arrays = true

    if prop_schema.items then
      return M._analyze_property(prop_schema.items, analysis, depth + 1)
    end
  end

  return depth
end

-- =============================================================================
-- Decision Table
-- =============================================================================

function M._apply_decision_table(analysis, opts)
  local threshold = opts.token_budget_threshold or 500

  -- Decision table (from design doc):
  -- 1. Flat + <=5 fields + NO constraints -> Instructional
  -- 2. Nested objects/arrays -> Few-shot
  -- 3. Has enums/const -> Few-shot
  -- 4. Has pattern constraints -> Few-shot
  -- 5. Token budget < threshold -> Instructional

  -- Rule 5: Token budget constrained
  -- (This check would need estimated token count, for now use heuristic)
  if analysis.field_count > 10 and threshold < 500 then
    return "instructional"
  end

  -- Rules 2-4: Complex schemas or constraints benefit from few-shot
  if analysis.has_nested_objects or analysis.has_arrays or
     analysis.has_enum or analysis.has_pattern or analysis.has_const then
    return "few-shot"
  end

  -- Rule 1: Flat schema with few fields and no special constraints
  if analysis.is_flat then
    return "instructional"
  end

  -- Default: instructional for simple cases
  return "instructional"
end

-- =============================================================================
-- Utilities
-- =============================================================================

function M.estimate_tokens(schema)
  -- Rough estimation of tokens needed for schema
  local count = 0

  if schema.type == "object" and schema.properties then
    for prop_name, prop_schema in pairs(schema.properties) do
      -- Count property name
      count = count + #prop_name

      -- Count type and constraints
      count = count + M.estimate_tokens(prop_schema)
    end
  elseif schema.type == "array" and schema.items then
    count = count + 10 + M.estimate_tokens(schema.items)
  else
    -- Base count for primitive types
    count = count + 5

    if schema.enum then
      count = count + #table.concat(schema.enum, ",")
    end

    if schema.pattern then
      count = count + #schema.pattern
    end
  end

  return count
end

return M
