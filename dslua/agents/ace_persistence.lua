-- dslua/agents/ace_persistence.lua
local json = require("dkjson")
local M = {}

function M.ExportLearnedWeights(filepath, rules, weights)
  local learned = {}

  for _, rule in ipairs(rules) do
    local current_weight = weights[rule.key] or rule.default_weight
    -- Only export if different from default
    if current_weight ~= rule.default_weight then
      learned[rule.key] = current_weight
    end
  end

  local json_str = json.encode(learned, {indent = true})

  local f, err = io.open(filepath, "w")
  if not f then
    return false, "Failed to open file: " .. err
  end

  f:write(json_str)
  f:close()

  return true, nil
end

function M.LoadWeightOverrides(filepath, rules)
  local f, err = io.open(filepath, "r")
  if not f then
    return nil, "Failed to open file: " .. err
  end

  local content = f:read("*all")
  f:close()

  local data, pos, err = json.decode(content, 1, nil)
  if not data then
    return nil, "Failed to parse JSON: " .. err
  end

  -- Validate all values are numbers
  for key, value in pairs(data) do
    if type(value) ~= "number" then
      return nil, string.format("Invalid weight for %s: expected number, got %s", key, type(value))
    end
  end

  return data, nil
end

return M
