-- dslua/structured/strategies/json_salvage.lua
-- JSON salvage strategy - extracts JSON from freeform text (post-processing)

local M = {}

local dkjson = require("dkjson")

-- =============================================================================
-- Main API
-- =============================================================================

function M.extract(text, schema, opts)
  opts = opts or {}

  if not text or text == "" or text:match("^%s*$") then
    return {
      success = false,
      candidate = nil,
      lossy = false,
      method = "none",
      error = "Empty or whitespace-only input"
    }
  end

  -- Try to extract JSON blocks
  local json_blocks = M._extract_json_blocks(text)

  if #json_blocks == 0 then
    return {
      success = false,
      candidate = nil,
      lossy = false,
      method = "none",
      error = "No JSON blocks found"
    }
  end

  -- Sort by size (largest first) - prefer most complete extraction
  table.sort(json_blocks, function(a, b)
    return #b.text < #a.text  -- Descending by length
  end)

  -- Filter by required top-level type if specified
  local filtered_blocks = json_blocks
  if opts.require_top_level then
    filtered_blocks = M._filter_by_type(json_blocks, opts.require_top_level)
  end

  -- Try to parse each block until one succeeds
  for _, block in ipairs(filtered_blocks) do
    local cleaned = M._clean_json(block.text)
    local candidate, parse_err = M._parse_json(cleaned)

    if candidate then
      -- Apply safe repairs
      local repaired = M._apply_safe_repairs(candidate)

      return {
        success = true,
        candidate = repaired,
        lossy = true,  -- Salvage is always lossy
        method = block.method,  -- "direct", "markdown", "code_block"
        raw_text = block.text,
        cleaned_text = cleaned,
        repairs = M._detect_repairs_needed(block.text, cleaned)
      }
    end
  end

  -- No valid JSON found
  return {
    success = false,
    candidate = nil,
    lossy = false,
    method = "failed",
    error = "Extracted blocks failed to parse",
    blocks_found = #json_blocks
  }
end

-- =============================================================================
-- JSON Block Extraction
-- =============================================================================

function M._extract_json_blocks(text)
  local blocks = {}

  -- Method 1: Direct object/array extraction
  local objects = M._extract_braced_blocks(text, "{", "}")
  for _, obj in ipairs(objects) do
    table.insert(blocks, {
      text = obj,
      method = "direct"
    })
  end

  -- Method 2: Direct array extraction
  local arrays = M._extract_braced_blocks(text, "%[", "%]")
  for _, arr in ipairs(arrays) do
    table.insert(blocks, {
      text = arr,
      method = "direct"
    })
  end

  -- Method 3: Markdown code blocks
  local markdown_blocks = M._extract_markdown_blocks(text)
  for _, block in ipairs(markdown_blocks) do
    table.insert(blocks, {
      text = block,
      method = "markdown"
    })
  end

  -- Method 4: Unmarked code blocks
  local unmarked = M._extract_unmarked_code_blocks(text)
  for _, block in ipairs(unmarked) do
    table.insert(blocks, {
      text = block,
      method = "code_block"
    })
  end

  return blocks
end

function M._extract_braced_blocks(text, open_char, close_char)
  local blocks = {}
  local pos = 1

  while pos <= #text do
    -- Find opening brace
    local start_pos = text:find(open_char, pos)
    if not start_pos then
      break
    end

    -- Find matching closing brace
    local depth = 1
    local end_pos = start_pos + 1
    local found = false

    while end_pos <= #text and depth > 0 do
      local char = text:sub(end_pos, end_pos)
      if char == open_char or (open_char == "%[" and char == "[") then
        depth = depth + 1
      elseif char == "}" or char == "]" then
        depth = depth - 1
        if depth == 0 then
          found = true
          break
        end
      end
      end_pos = end_pos + 1
    end

    if found then
      local block = text:sub(start_pos, end_pos)
      table.insert(blocks, block)
      pos = end_pos + 1
    else
      pos = start_pos + 1
    end
  end

  return blocks
end

function M._extract_markdown_blocks(text)
  local blocks = {}

  -- Match ```json ... ``` or ``` ... ```
  for block in text:gmatch("```[^\n]*\n(.-)```") do
    table.insert(blocks, block)
  end

  -- Also match ```...``` without newlines
  for block in text:gmatch("```(.-)```") do
    if not block:match("\n") then
      table.insert(blocks, block)
    end
  end

  return blocks
end

function M._extract_unmarked_code_blocks(text)
  local blocks = {}

  -- Look for lines with content that looks like JSON
  for line in text:gmatch("[^\r\n]+") do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed and #trimmed > 0 then
      local first_char = trimmed:sub(1, 1)
      if first_char == "{" or first_char == "[" then
        table.insert(blocks, trimmed)
      end
    end
  end

  return blocks
end

-- =============================================================================
-- Filtering
-- =============================================================================

function M._filter_by_type(blocks, required_type)
  local filtered = {}

  for _, block in ipairs(blocks) do
    local text = block.text:gsub("%s+", ""):gsub("^%s+", ""):gsub("%s+$", "")
    local first_char = text:sub(1, 1)

    if required_type == "object" and first_char == "{" then
      table.insert(filtered, block)
    elseif required_type == "array" and first_char == "[" then
      table.insert(filtered, block)
    elseif required_type == nil then
      table.insert(filtered, block)
    end
  end

  return filtered
end

-- =============================================================================
-- Cleaning and Repair
-- =============================================================================

function M._clean_json(json_str)
  local cleaned = json_str

  -- Remove markdown fences if present
  cleaned = cleaned:gsub("```[^\n]*\n?", "")
  cleaned = cleaned:gsub("%s*```%s*", "")

  -- Remove common prefixes/suffixes
  cleaned = cleaned:gsub("^JSON:%s*", "")
  cleaned = cleaned:gsub("^json:%s*", "")
  cleaned = cleaned:gsub("^Result:%s*", "")

  return cleaned
end

function M._apply_safe_repairs(data)
  -- Safe repairs are non-semantic only
  -- This is a placeholder for future repair logic
  -- Currently just returns data as-is
  return data
end

function M._detect_repairs_needed(original, cleaned)
  local repairs = {}

  if original ~= cleaned then
    table.insert(repairs, "cleaned")
  end

  return repairs
end

-- =============================================================================
-- Parsing
-- =============================================================================

function M._parse_json(str)
  if not str or str == "" then
    return nil, "Empty string"
  end

  local data, pos, err = dkjson.decode(str, 1, nil)

  if not data then
    return nil, err or "Parse error"
  end

  return data, nil
end

-- =============================================================================
-- Utilities
-- =============================================================================

function M.is_json_text(text)
  local trimmed = text:gsub("^%s+", ""):gsub("%s+$", "")
  if #trimmed == 0 then
    return false
  end

  local first_char = trimmed:sub(1, 1)
  return first_char == "{" or first_char == "["
end

return M
