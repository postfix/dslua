-- dslua/structured/decorator.lua
-- StructuredOutput decorator - validates and enforces JSON schema compliance

local M = {}

local dkjson = require("dkjson")
local Validator = require("dslua.structured.validator")
local Types = require("dslua.structured.types")

-- =============================================================================
-- Constructor
-- =============================================================================

function M.new(module, schema, opts)
  opts = opts or {}

  local self = {
    _module = module,
    _schema = schema,
    _opts = opts,
    _mode = opts.mode or "structured"
  }

  setmetatable(self, M)
  return self
end

M.__index = M

-- =============================================================================
-- Main Process Method
-- =============================================================================

function M:Process(ctx, input)
  -- Validate configuration
  if not self._schema then
    return Types.ErrorResult(
      Types.ErrorCodes.SCHEMA_INVALID,
      "Schema is required for structured and template modes",
      "process"
    )
  end

  -- Capture start time for timeout
  local start_time = os.clock()
  local deadline_ms = ctx.deadline_ms
  local timeout_ms = self._opts.timeout_ms or 30000

  -- Attempt 0: Run module and validate
  local response = self._module:Process(ctx, input)

  -- Check for timeout
  if deadline_ms and (os.time() * 1000 > deadline_ms) then
    return Types.ErrorResult(
      Types.ErrorCodes.TIMEOUT,
      "Operation exceeded deadline",
      "process"
    )
  end

  -- Stage 1: Parse JSON
  local json_candidate, parse_err = self:_parse_json(response.content)
  local repair_operations = {}

  if not json_candidate then
    -- Parse failed - try repair first
    json_candidate = self:_repair_json(response.content)

    if json_candidate then
      -- Repair succeeded
      table.insert(repair_operations, "json_repaired")
    else
      -- Repair also failed
      local diagnostics = {parse_error = parse_err}
      local context = {
        last_raw_output = Types.Truncate(response.content, self._opts.max_error_output_chars or 500)
      }

      -- Check if we can retry
      if self._opts.max_retries and self._opts.max_retries > 0 then
        if response.prompt then
          return self:_retry_with_validation_error(ctx, response, 0, "parse", diagnostics, context)
        else
          return Types.ErrorResult(
            Types.ErrorCodes.RETRY_UNSUPPORTED,
            "Retries require response.prompt; module did not provide it",
            "parse"
          )
        end
      else
        return Types.ErrorResult(
          Types.ErrorCodes.JSON_PARSE,
          "Failed to parse JSON: " .. parse_err,
          "parse",
          diagnostics,
          context
        )
      end
    end
  end

  -- Stage 2: Validate against schema
  local validation_result = Validator.validate(json_candidate, self._schema)

  if not validation_result.ok then
    -- Validation failed
    local diagnostics = {validation_errors = validation_result.errors}
    local context = {
      last_raw_output = Types.Truncate(response.content, self._opts.max_error_output_chars or 500)
    }

    -- Check if we should retry
    if self._opts.max_retries and self._opts.max_retries > 0 then
      if response.prompt then
        return self:_retry_with_validation_error(ctx, response, 0, "validate", diagnostics, context)
      else
        return Types.ErrorResult(
          Types.ErrorCodes.RETRY_UNSUPPORTED,
          "Retries require response.prompt; module did not provide it",
          "validate"
        )
      end
    else
      return Types.ErrorResult(
        Types.ErrorCodes.SCHEMA_VALIDATION,
        "Schema validation failed",
        "validate",
        diagnostics,
        context
      )
    end
  end

  -- Determine provenance source
  local source = Types.ProvenanceSource.STRICT
  if #repair_operations > 0 then
    source = Types.ProvenanceSource.REPAIRED
  end

  -- Build result envelope
  local provenance = Types.Provenance(source, 0, repair_operations, {})

  local debug_info = nil
  if self._opts.debug_enabled then
    debug_info = {
      raw_response = self._opts.include_raw_response and response.content or nil,
      validation_time_ms = math.floor((os.clock() - start_time) * 1000),
      retry_history = {}
    }
  end

  return Types.SuccessResult(json_candidate, provenance, debug_info)
end

-- =============================================================================
-- Retry Logic
-- =============================================================================

function M:_retry_with_validation_error(ctx, response, attempt_num, stage, diagnostics, context)
  local max_retries = self._opts.max_retries or 2

  if attempt_num >= max_retries then
    context.retry_count = attempt_num
    return Types.ErrorResult(
      Types.ErrorCodes.MAX_RETRIES,
      string.format("Maximum retries (%d) exceeded", max_retries),
      stage,
      diagnostics,
      context
    )
  end

  -- Build retry prompt
  local retry_prompt = self:_build_retry_prompt(response, diagnostics, context)

  -- Call LLM directly (not the module!) with low temperature
  local llm = ctx:LLM()
  if not llm then
    return Types.ErrorResult(
      Types.ErrorCodes.TIMEOUT,
      "No LLM available in context",
      "retry"
    )
  end

  local retry_opts = {
    temperature = self._opts.retry_temperature or 0
  }

  if self._opts.retry_top_p then
    retry_opts.top_p = self._opts.retry_top_p
  end

  local retry_response = llm:Complete(ctx, retry_prompt, retry_opts)

  -- Try to parse and validate the retry response
  local json_candidate, parse_err = self:_parse_json(retry_response.content)

  if not json_candidate then
    -- Try repair
    json_candidate = self:_repair_json(retry_response.content)
  end

  if not json_candidate then
    -- Still failed - recurse to next retry
    return self:_retry_with_validation_error(
      ctx,
      {prompt = retry_prompt, content = retry_response.content},
      attempt_num + 1,
      "parse",
      {parse_error = parse_err},
      {last_raw_output = Types.Truncate(retry_response.content, 200)}
    )
  end

  -- Validate
  local validation_result = Validator.validate(json_candidate, self._schema)

  if not validation_result.ok then
    -- Validation failed - recurse to next retry
    return self:_retry_with_validation_error(
      ctx,
      {prompt = retry_prompt, content = retry_response.content},
      attempt_num + 1,
      "validate",
      {validation_errors = validation_result.errors},
      {last_raw_output = Types.Truncate(retry_response.content, 200)}
    )
  end

  -- Success! Build result envelope with retry provenance
  local provenance = Types.Provenance(
    Types.ProvenanceSource.RETRIED,
    attempt_num + 1,
    {},
    {}
  )

  local debug_info = nil
  if self._opts.debug_enabled then
    debug_info = {
      raw_response = self._opts.include_raw_response and retry_response.content or nil,
      retry_history = {attempt_num + 1}
    }
  end

  return Types.SuccessResult(json_candidate, provenance, debug_info)
end

function M:_build_retry_prompt(response, diagnostics, context)
  local parts = {}

  table.insert(parts, "Your previous response was invalid. Please fix and return valid JSON only.")
  table.insert(parts, "")
  table.insert(parts, "[ERROR DETAILS]")
  table.insert(parts, string.format("Validation failed at stage: %s", diagnostics.parse_error and "parse" or "validate"))
  table.insert(parts, "")

  -- Add validation errors
  if diagnostics.validation_errors then
    table.insert(parts, "Schema Validation Errors:")
    for _, err in ipairs(diagnostics.validation_errors) do
      table.insert(parts, string.format("- Path: %s", err.path))
      table.insert(parts, string.format("  Expected: %s", err.expected))
      table.insert(parts, string.format("  Got: %s", err.actual))
      table.insert(parts, string.format("  Error: %s", err.keyword))
    end
    table.insert(parts, "")
  end

  -- Add parse error
  if diagnostics.parse_error then
    table.insert(parts, string.format("JSON Parse Error: %s", diagnostics.parse_error))
    table.insert(parts, "")
  end

  table.insert(parts, "[REQUIRED OUTPUT FORMAT]")
  table.insert(parts, "Return ONLY valid JSON. No markdown. No commentary. No explanation.")
  table.insert(parts, "Do not include the schema in your output.")
  table.insert(parts, "Output must be only the JSON result.")
  table.insert(parts, "Return a single JSON object or array that conforms to the schema.")
  table.insert(parts, "")

  table.insert(parts, "[SCHEMA]")
  table.insert(parts, dkjson.encode(self._schema, {indent = false}))
  table.insert(parts, "")

  table.insert(parts, "[ORIGINAL REQUEST]")
  table.insert(parts, response.prompt or "")
  table.insert(parts, "")
  table.insert(parts, "Try again:")

  return table.concat(parts, "\n")
end

-- =============================================================================
-- JSON Parsing
-- =============================================================================

function M:_parse_json(content)
  if not content or content == "" then
    return nil, "Empty content"
  end

  local data, pos, err = dkjson.decode(content, 1, nil)

  if not data then
    return nil, err or "Parse error"
  end

  return data, nil
end

-- =============================================================================
-- Safe JSON Repair
-- =============================================================================

function M:_repair_json(content)
  local repaired = content

  -- Remove markdown fences
  if self._opts.repair_markdown_fences then
    -- Remove ```json ... ``` or ``` ... ```
    repaired = repaired:gsub("```json[^\n]*", "")
    repaired = repaired:gsub("```[^\n]*", "")
    repaired = repaired:gsub("%s*```%s*.*$", "")
  end

  -- Remove trailing commas
  if self._opts.repair_trailing_commas then
    -- Remove trailing comma before ] or }
    repaired = repaired:gsub(",%s*]", "]")
    repaired = repaired:gsub(",%s*}", "}")
  end

  -- Normalize quotes (smart quotes to ASCII quotes)
  if self._opts.repair_normalize_quotes then
    repaired = repaired:gsub("\226\128\156", "\"")  -- Left smart quote
    repaired = repaired:gsub("\226\128\157", "\"")  -- Right smart quote
    repaired = repaired:gsub("\226\128\152", "\34")  -- Left single quote
    repaired = repaired:gsub("\226\128\153", "\39")  -- Right single quote
  end

  -- Try to parse the repaired version
  local data, err = self:_parse_json(repaired)

  if data then
    return data
  else
    return nil
  end
end

return M
