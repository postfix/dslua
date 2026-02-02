-- dslua/adapters/xml.lua
-- XML Structured Output Adapter

local M = {}

-- =============================================================================
-- XML Adapter
-- =============================================================================

M.XMLAdapter = {}
M.XMLAdapter.__index = M.XMLAdapter

function M.XMLAdapter.new(opts)
  opts = opts or {}

  local self = {
    -- Schema definition
    schema = opts.schema or {},

    -- XML formatting options
    root_element = opts.root_element or "output",
    indent = opts.indent or 2,
    declaration = opts.declaration ~= false,

    -- Validation
    strict = opts.strict ~= false,
    allow_extra_fields = opts.allow_extra_fields or false,

    -- Error handling
    on_error = opts.on_error or "error"  -- "error", "repair", "ignore"
  }

  setmetatable(self, M.XMLAdapter)
  return self
end

-- Parse XML response
function M.XMLAdapter:parse(xml_text, schema)
  schema = schema or self.schema

  local ok, result, err = pcall(function()
    return self:_parse_xml(xml_text, schema)
  end)

  if not ok then
    if self.on_error == "repair" then
      local repaired = self:_repair_xml(xml_text, schema)
      return repaired
    elseif self.on_error == "ignore" then
      return {success = false, data = nil, provenance = "ignored"}
    else
      return nil, type(result) == "string" and result or "Parse error"
    end
  end

  -- Handle case where parsing returned nil with error (not thrown)
  if not result then
    if self.on_error == "repair" then
      local repaired = self:_repair_xml(xml_text, schema)
      return repaired
    elseif self.on_error == "ignore" then
      return {success = false, data = nil, provenance = "ignored"}
    else
      return nil, err or "Parse error"
    end
  end

  return result
end

-- Internal XML parser (simple implementation)
function M.XMLAdapter:_parse_xml(xml_text, schema)
  -- Remove XML declaration if present
  local text = xml_text:gsub("^<%?xml[^>]*%?>%s*", "")

  -- Parse root element
  local root_open = text:match("<([%w:]+)[^>]*>")
  if not root_open then
    return nil, "No root element found"
  end

  -- Extract content between root tags
  local content_pattern = "<" .. root_open .. "[^>]*>(.-)</" .. root_open .. ">"
  local content = text:match(content_pattern)

  if not content then
    return nil, "Could not extract root content"
  end

  -- Parse fields based on schema
  local result = {}
  for field_name, field_def in pairs(schema) do
    local pattern = "<" .. field_name .. ">(.-)</" .. field_name .. ">"
    local value = content:match(pattern)

    if value then
      -- Trim whitespace
      value = value:gsub("^%s+", ""):gsub("%s+$", "")

      -- Convert type
      if field_def.type == "number" then
        value = tonumber(value)
      elseif field_def.type == "boolean" then
        value = value == "true"
      elseif field_def.type == "array" then
        value = self:_parse_array(value, field_def.item_type)
      elseif field_def.type == "object" then
        value = self:_parse_object(value, field_def.properties)
      end

      result[field_name] = value
    elseif field_def.required then
      return nil, "Missing required field: " .. field_name
    end
  end

  return {
    success = true,
    data = result,
    provenance = "strict"
  }
end

-- Parse array elements
function M.XMLAdapter:_parse_array(xml_text, item_type)
  local items = {}

  -- Match item elements
  local pattern = "<item>(.-)</item>"
  for item_text in xml_text:gmatch(pattern) do
    local value = item_text:gsub("^%s+", ""):gsub("%s+$", "")

    if item_type == "number" then
      value = tonumber(value)
    elseif item_type == "boolean" then
      value = value == "true"
    end

    table.insert(items, value)
  end

  return items
end

-- Parse nested object
function M.XMLAdapter:_parse_object(xml_text, properties)
  local obj = {}

  for prop_name, prop_def in pairs(properties) do
    local pattern = "<" .. prop_name .. ">(.-)</" .. prop_name .. ">"
    local value = xml_text:match(pattern)

    if value then
      value = value:gsub("^%s+", ""):gsub("%s+$", "")

      if prop_def.type == "number" then
        value = tonumber(value)
      elseif prop_def.type == "boolean" then
        value = value == "true"
      elseif prop_def.type == "array" then
        value = self:_parse_array(value, prop_def.item_type)
      elseif prop_def.type == "object" then
        value = self:_parse_object(value, prop_def.properties)
      end

      obj[prop_name] = value
    elseif prop_def.required then
      return nil, "Missing required field: " .. prop_name
    end
  end

  return obj
end

-- Repair malformed XML
function M.XMLAdapter:_repair_xml(xml_text, schema)
  -- Simple repair strategies
  local repaired = xml_text

  -- Add missing root element if none present
  if not repaired:match("^<%w+") then
    repaired = "<" .. self.root_element .. ">" .. repaired .. "</" .. self.root_element .. ">"
  end

  -- Try parsing with repaired XML
  local ok, result = pcall(function()
    return self:_parse_xml(repaired, schema)
  end)

  if ok and result and result.data then
    result.provenance = "repaired"
    return result
  end

  -- If still fails, return empty with repair provenance
  return {
    success = true,
    data = {},
    provenance = "repaired",
    warning = "Could not fully repair XML"
  }
end

-- Generate XML from table
function M.XMLAdapter:generate(data, schema)
  schema = schema or self.schema

  local lines = {}

  -- Add XML declaration
  if self.declaration then
    table.insert(lines, '<?xml version="1.0" encoding="UTF-8"?>')
  end

  -- Add root opening tag
  local indent_str = string.rep(" ", self.indent)
  table.insert(lines, "<" .. self.root_element .. ">")

  -- Add fields
  for field_name, value in pairs(data) do
    local field_def = schema[field_name]

    if field_def then
      local field_xml = self:_generate_field(field_name, value, field_def, indent_str)
      table.insert(lines, field_xml)
    elseif not self.strict or self.allow_extra_fields then
      -- Unknown field, include as string
      table.insert(lines, indent_str .. "  <" .. field_name .. ">" .. tostring(value) .. "</" .. field_name .. ">")
    end
  end

  -- Add root closing tag
  table.insert(lines, "</" .. self.root_element .. ">")

  return table.concat(lines, "\n")
end

-- Generate field XML
function M.XMLAdapter:_generate_field(name, value, field_def, indent)
  local inner_indent = indent .. string.rep(" ", self.indent)

  if field_def.type == "array" then
    -- Generate array
    local parts = {}
    table.insert(parts, indent .. "  <" .. name .. ">")

    for _, item in ipairs(value) do
      local item_xml = self:_generate_value(item, field_def.item_type, inner_indent)
      table.insert(parts, inner_indent .. "<item>" .. item_xml .. "</item>")
    end

    table.insert(parts, indent .. "  </" .. name .. ">")
    return table.concat(parts, "\n")

  elseif field_def.type == "object" then
    -- Generate nested object
    local parts = {}
    table.insert(parts, indent .. "  <" .. name .. ">")

    for prop_name, prop_value in pairs(value) do
      local prop_def = field_def.properties[prop_name]
      if prop_def then
        local prop_xml = self:_generate_field(prop_name, prop_value, prop_def, inner_indent)
        table.insert(parts, prop_xml)
      end
    end

    table.insert(parts, indent .. "  </" .. name .. ">")
    return table.concat(parts, "\n")

  else
    -- Simple field
    local value_xml = self:_generate_value(value, field_def.type, indent .. "  ")
    return indent .. "  <" .. name .. ">" .. value_xml .. "</" .. name .. ">"
  end
end

-- Generate value string
function M.XMLAdapter:_generate_value(value, value_type, indent)
  if value_type == "string" then
    return value
  elseif value_type == "number" then
    return tostring(value)
  elseif value_type == "boolean" then
    return value and "true" or "false"
  else
    return tostring(value)
  end
end

-- =============================================================================
-- Schema Builder
-- =============================================================================

M.SchemaBuilder = {}
M.SchemaBuilder.__index = M.SchemaBuilder

function M.SchemaBuilder.new()
  local self = {
    fields = {}
  }

  setmetatable(self, M.SchemaBuilder)
  return self
end

function M.SchemaBuilder:string(name, required)
  self.fields[name] = {type = "string", required = required}
  return self
end

function M.SchemaBuilder:number(name, required)
  self.fields[name] = {type = "number", required = required}
  return self
end

function M.SchemaBuilder:boolean(name, required)
  self.fields[name] = {type = "boolean", required = required}
  return self
end

function M.SchemaBuilder:array(name, item_type, required)
  self.fields[name] = {type = "array", item_type = item_type, required = required}
  return self
end

function M.SchemaBuilder:object(name, properties, required)
  self.fields[name] = {type = "object", properties = properties, required = required}
  return self
end

function M.SchemaBuilder:build()
  return self.fields
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

function M.xml_adapter(opts)
  return M.XMLAdapter.new(opts)
end

function M.schema_builder()
  return M.SchemaBuilder.new()
end

return M
