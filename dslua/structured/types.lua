-- dslua/structured/types.lua
-- Shared type definitions and constants for structured output framework

local M = {}

-- =============================================================================
-- Error Codes (Stable Taxonomy)
-- =============================================================================

M.ErrorCodes = {
  JSON_PARSE = "ERR_JSON_PARSE",
  SCHEMA_VALIDATION = "ERR_SCHEMA_VALIDATION",
  MAX_RETRIES = "ERR_MAX_RETRIES",
  RETRY_UNSUPPORTED = "ERR_RETRY_UNSUPPORTED",
  SCHEMA_INVALID = "ERR_SCHEMA_INVALID",
  UNSUPPORTED_KEYWORD = "ERR_UNSUPPORTED_KEYWORD",
  TIMEOUT = "ERR_TIMEOUT",
  INVALID_OPTION = "ERR_INVALID_OPTION",
}

-- =============================================================================
-- Provenance Source Types
-- =============================================================================

M.ProvenanceSource = {
  STRICT = "strict",      -- Passed validation on first attempt
  REPAIRED = "repaired",  -- Passed after safe syntactic repairs
  RETRIED = "retried"     -- Passed after one or more retries
}

-- =============================================================================
-- Validation Stages
-- =============================================================================

M.ValidationStage = {
  PARSE = "parse",
  VALIDATE = "validate",
  REPAIR = "repair"
}

-- =============================================================================
-- ResultEnvelope Factory Functions
-- =============================================================================

--- Create a success result envelope
-- @param data table Parsed JSON data as Lua table
-- @param provenance table Provenance metadata
-- @param debug table Optional debug information
-- @return table ResultEnvelope with success=true
function M.SuccessResult(data, provenance, debug)
  local result = {
    success = true,
    data = data,
    provenance = provenance or {
      source = M.ProvenanceSource.STRICT,
      attempt_count = 0,
      repair_operations = {},
      warnings = {}
    }
  }

  if debug then
    result.debug = debug
  end

  return result
end

--- Create a failure result envelope
-- @param error_code string Error code from ErrorCodes
-- @param message string Human-readable error message
-- @param stage string Validation stage
-- @param diagnostics table Optional diagnostic details
-- @param context table Optional context information
-- @return table ResultEnvelope with success=false
function M.ErrorResult(error_code, message, stage, diagnostics, context)
  local result = {
    success = false,
    error = {
      code = error_code,
      message = message,
      stage = stage,
      recoverable = M._isRecoverable(error_code)
    }
  }

  -- Add optional diagnostics
  if diagnostics then
    if diagnostics.validation_errors then
      result.error.validation_errors = diagnostics.validation_errors
    end
    if diagnostics.parse_error then
      result.error.parse_error = diagnostics.parse_error
    end
  end

  -- Add optional context
  if context then
    if context.last_raw_output then
      result.error.last_raw_output = context.last_raw_output
    end
    if context.retry_count then
      result.error.retry_count = context.retry_count
    end
    if context.schema_id then
      result.error.schema_id = context.schema_id
    end
  end

  return result
end

-- =============================================================================
-- Internal Helpers
-- =============================================================================

--- Determine if error code is recoverable
-- @param error_code string Error code from ErrorCodes
-- @return boolean True if error is recoverable
function M._isRecoverable(error_code)
  local recoverable = {
    [M.ErrorCodes.JSON_PARSE] = true,
    [M.ErrorCodes.SCHEMA_VALIDATION] = true,
    [M.ErrorCodes.MAX_RETRIES] = true,
  }
  return recoverable[error_code] or false
end

--- Create a provenance metadata object
-- @param source string Provenance source type (default: "strict")
-- @param attempt_count number Number of attempts made (default: 0)
-- @param repair_operations table List of repair operations applied (default: {})
-- @param warnings table Optional warnings (default: {})
-- @return table Provenance metadata
function M.Provenance(source, attempt_count, repair_operations, warnings)
  return {
    source = source or M.ProvenanceSource.STRICT,
    attempt_count = attempt_count or 0,
    repair_operations = repair_operations or {},
    warnings = warnings or {}
  }
end

--- Truncate string to max length (for error/debug output)
-- @param str string String to truncate
-- @param max_chars number Maximum characters
-- @param suffix string Optional suffix to add if truncated
-- @return string Truncated string
function M.Truncate(str, max_chars, suffix)
  suffix = suffix or "..."
  if not str or #str <= max_chars then
    return str
  end

  -- Leave room for suffix
  local keep = max_chars - #suffix
  if keep < 1 then
    keep = 0
  end

  return string.sub(str, 1, keep) .. suffix
end

return M
