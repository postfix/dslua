-- specs/tools/coverage.lua
-- Test coverage measurement tool

local M = {}

-- Simple coverage analyzer
function M.analyze_coverage(module_pattern)
  module_pattern = module_pattern or "dslua"

  local coverage_data = {
    total_files = 0,
    tested_files = 0,
    total_functions = 0,
    tested_functions = 0,
    files = {}
  }

  -- Find all Lua files in dslua directory
  local find_cmd = "find dslua -name '*.lua' -type f"
  local pipe = io.popen(find_cmd)
  if not pipe then
    return nil, "Failed to find Lua files"
  end

  local files = {}
  for file in pipe:lines() do
    table.insert(files, file)
  end
  pipe:close()

  -- Find all spec files
  local spec_cmd = "find specs -name '*_spec.lua' -type f"
  local spec_pipe = io.popen(spec_cmd)
  local spec_files = {}
  if spec_pipe then
    for file in spec_pipe:lines() do
      table.insert(spec_files, file)
    end
    spec_pipe:close()
  end

  -- Analyze each file
  for _, file in ipairs(files) do
    local file_info = M.analyze_file(file, spec_files)
    if file_info then
      table.insert(coverage_data.files, file_info)
      coverage_data.total_files = coverage_data.total_files + 1
      coverage_data.total_functions = coverage_data.total_functions + file_info.total_functions
      coverage_data.tested_functions = coverage_data.tested_functions + file_info.tested_functions

      if file_info.has_spec then
        coverage_data.tested_files = coverage_data.tested_files + 1
      end
    end
  end

  return coverage_data
end

-- Analyze a single file
function M.analyze_file(file, spec_files)
  local f = io.open(file, "r")
  if not f then
    return nil
  end

  local content = f:read("*all")
  f:close()

  local functions = {}
  local module_name = file:gsub("^dslua/", ""):gsub("%.lua$", ""):gsub("/", ".")

  -- Find all function definitions
  for line in content:gmatch("[^\r\n]+") do
    -- Match: function M.name, function Name.new, M.name = function
    local fn = line:match("%s*function%s+%w+%.([%w_]+)%(") or
             line:match("%s*function%s+%w+%.([%w_]+)%.([%w_]+)%(") or
             line:match("%s*function%s+([%w_]+)%.([%w_]+)%(") or
             line:match("%s*([%w_]+)%.([%w_]+)%s*=%s*function%s*%(")

    if fn then
      local full_name = type(fn) == "table" and (fn[1] .. "." .. fn[2]) or fn
      table.insert(functions, {
        name = full_name,
        line = line,
        tested = false
      })
    end
  end

  -- Check if spec file exists and tests this module
  local spec_file = file:gsub("^dslua/", "specs/"):gsub("%.lua$", "_spec.lua")
  local has_spec = false
  local tested_functions = 0

  for _, spec in ipairs(spec_files) do
    if spec == spec_file then
      has_spec = true

      -- Check which functions are tested
      local spec_f = io.open(spec, "r")
      if spec_f then
        local spec_content = spec_f:read("*all")
        spec_f:close()

        for _, fn in ipairs(functions) do
          local fn_name = fn.name:gsub("^.+%.", "")  -- Get just the function name
          if spec_content:match(fn_name) then
            fn.tested = true
            tested_functions = tested_functions + 1
          end
        end
      end

      break
    end
  end

  return {
    file = file,
    module = module_name,
    has_spec = has_spec,
    total_functions = #functions,
    tested_functions = tested_functions,
    functions = functions
  }
end

-- Generate coverage report
function M.generate_report(coverage_data)
  local lines = {}
  table.insert(lines, "\n=== Test Coverage Report ===\n")

  -- Overall statistics
  local file_coverage = (coverage_data.tested_files / coverage_data.total_files) * 100
  local function_coverage = (coverage_data.tested_functions / coverage_data.total_functions) * 100

  table.insert(lines, string.format("Total Files: %d", coverage_data.total_files))
  table.insert(lines, string.format("Files with Specs: %d (%.1f%%)",
    coverage_data.tested_files, file_coverage))
  table.insert(lines, string.format("Total Functions: %d", coverage_data.total_functions))
  table.insert(lines, string.format("Tested Functions: %d (%.1f%%)",
    coverage_data.tested_functions, function_coverage))
  table.insert(lines, "")

  -- Uncovered files
  table.insert(lines, "Files without tests:")
  for _, file_info in ipairs(coverage_data.files) do
    if not file_info.has_spec then
      table.insert(lines, string.format("  - %s (%d functions)",
        file_info.file, file_info.total_functions))
    end
  end
  table.insert(lines, "")

  -- Files with low function coverage
  table.insert(lines, "Files with incomplete function coverage:")
  for _, file_info in ipairs(coverage_data.files) do
    if file_info.has_spec and file_info.tested_functions < file_info.total_functions then
      local coverage = (file_info.tested_functions / file_info.total_functions) * 100
      table.insert(lines, string.format("  - %s (%.0f%% - %d/%d functions)",
        file_info.file, coverage, file_info.tested_functions, file_info.total_functions))
    end
  end
  table.insert(lines, "")

  return table.concat(lines, "\n")
end

-- Run if executed directly
if arg and arg[0] and arg[0]:match("coverage%.lua") then
  local coverage = M.analyze_coverage()
  if coverage then
    print(M.generate_report(coverage))
  end
end

return M
