-- specs/structured/types_spec.lua
-- Tests for dslua/structured/types.lua

local Types = require("dslua.structured.types")

describe("Structured Output Types", function()

  describe("ErrorCodes", function()
    it("should have all stable error codes defined", function()
      assert.is_not_nil(Types.ErrorCodes.JSON_PARSE)
      assert.is_not_nil(Types.ErrorCodes.SCHEMA_VALIDATION)
      assert.is_not_nil(Types.ErrorCodes.MAX_RETRIES)
      assert.is_not_nil(Types.ErrorCodes.RETRY_UNSUPPORTED)
      assert.is_not_nil(Types.ErrorCodes.SCHEMA_INVALID)
      assert.is_not_nil(Types.ErrorCodes.UNSUPPORTED_KEYWORD)
      assert.is_not_nil(Types.ErrorCodes.TIMEOUT)
      assert.is_not_nil(Types.ErrorCodes.INVALID_OPTION)

      assert.is.equal("ERR_JSON_PARSE", Types.ErrorCodes.JSON_PARSE)
      assert.is.equal("ERR_SCHEMA_VALIDATION", Types.ErrorCodes.SCHEMA_VALIDATION)
    end)
  end)

  describe("ProvenanceSource", function()
    it("should have all provenance source types", function()
      assert.is_not_nil(Types.ProvenanceSource.STRICT)
      assert.is_not_nil(Types.ProvenanceSource.REPAIRED)
      assert.is_not_nil(Types.ProvenanceSource.RETRIED)

      assert.is.equal("strict", Types.ProvenanceSource.STRICT)
      assert.is.equal("repaired", Types.ProvenanceSource.REPAIRED)
      assert.is.equal("retried", Types.ProvenanceSource.RETRIED)
    end)
  end)

  describe("ValidationStage", function()
    it("should have all validation stages", function()
      assert.is_not_nil(Types.ValidationStage.PARSE)
      assert.is_not_nil(Types.ValidationStage.VALIDATE)
      assert.is_not_nil(Types.ValidationStage.REPAIR)

      assert.is.equal("parse", Types.ValidationStage.PARSE)
      assert.is.equal("validate", Types.ValidationStage.VALIDATE)
      assert.is.equal("repair", Types.ValidationStage.REPAIR)
    end)
  end)

  describe("SuccessResult", function()
    it("should create a success result envelope", function()
      local data = {name = "Alice", age = 30}
      local provenance = Types.Provenance(Types.ProvenanceSource.STRICT, 0, {}, {})

      local result = Types.SuccessResult(data, provenance)

      assert.is_true(result.success)
      assert.is_same(data, result.data)
      assert.is_not_nil(result.provenance)
      assert.is.equal("strict", result.provenance.source)
      assert.is_equal(0, result.provenance.attempt_count)
      assert.is_nil(result.debug)
    end)

    it("should include debug info when provided", function()
      local data = {test = "data"}
      local debug_info = {
        raw_response = "test response",
        validation_time_ms = 45
      }

      local result = Types.SuccessResult(data, nil, debug_info)

      assert.is_true(result.success)
      assert.is_not_nil(result.debug)
      assert.is.equal("test response", result.debug.raw_response)
      assert.is_equal(45, result.debug.validation_time_ms)
    end)

    it("should use default provenance when not provided", function()
      local data = {test = "data"}
      local result = Types.SuccessResult(data)

      assert.is_true(result.success)
      assert.is_not_nil(result.provenance)
      assert.is.equal("strict", result.provenance.source)
      assert.is_equal(0, result.provenance.attempt_count)
    end)
  end)

  describe("ErrorResult", function()
    it("should create an error result envelope", function()
      local result = Types.ErrorResult(
        Types.ErrorCodes.JSON_PARSE,
        "Invalid JSON syntax",
        Types.ValidationStage.PARSE,
        {parse_error = "Unexpected token at position 42"},
        {retry_count = 1, schema_id = "test_schema"}
      )

      assert.is_false(result.success)
      assert.is_not_nil(result.error)
      assert.is.equal(Types.ErrorCodes.JSON_PARSE, result.error.code)
      assert.is.equal("Invalid JSON syntax", result.error.message)
      assert.is.equal("parse", result.error.stage)
      assert.is_true(result.error.recoverable)
      assert.is.equal("Unexpected token at position 42", result.error.parse_error)
      assert.is_equal(1, result.error.retry_count)
      assert.is.equal("test_schema", result.error.schema_id)
    end)

    it("should mark correct error codes as recoverable", function()
      local recoverable_errors = {
        Types.ErrorCodes.JSON_PARSE,
        Types.ErrorCodes.SCHEMA_VALIDATION,
        Types.ErrorCodes.MAX_RETRIES
      }

      for _, code in ipairs(recoverable_errors) do
        local result = Types.ErrorResult(code, "test", Types.ValidationStage.PARSE)
        assert.is_true(result.error.recoverable, "Error " .. code .. " should be recoverable")
      end
    end)

    it("should mark other error codes as not recoverable", function()
      local non_recoverable_errors = {
        Types.ErrorCodes.RETRY_UNSUPPORTED,
        Types.ErrorCodes.SCHEMA_INVALID,
        Types.ErrorCodes.UNSUPPORTED_KEYWORD,
        Types.ErrorCodes.TIMEOUT,
        Types.ErrorCodes.INVALID_OPTION
      }

      for _, code in ipairs(non_recoverable_errors) do
        local result = Types.ErrorResult(code, "test", Types.ValidationStage.PARSE)
        assert.is_false(result.error.recoverable, "Error " .. code .. " should not be recoverable")
      end
    end)

    it("should handle nil diagnostics gracefully", function()
      local result = Types.ErrorResult(
        Types.ErrorCodes.SCHEMA_VALIDATION,
        "Validation failed",
        Types.ValidationStage.VALIDATE,
        nil,  -- No diagnostics
        nil   -- No context
      )

      assert.is_false(result.success)
      assert.is_nil(result.error.validation_errors)
      assert.is_nil(result.error.parse_error)
      assert.is_nil(result.error.last_raw_output)
    end)
  end)

  describe("Provenance", function()
    it("should create provenance metadata", function()
      local prov = Types.Provenance(
        Types.ProvenanceSource.REPAIRED,
        1,
        {"markdown_removed", "trailing_commas_fixed"},
        {"minor formatting issues"}
      )

      assert.is.equal("repaired", prov.source)
      assert.is_equal(1, prov.attempt_count)
      assert.is_same({"markdown_removed", "trailing_commas_fixed"}, prov.repair_operations)
      assert.is_same({"minor formatting issues"}, prov.warnings)
    end)

    it("should use defaults when parameters not provided", function()
      local prov = Types.Provenance()

      assert.is.equal("strict", prov.source)
      assert.is_equal(0, prov.attempt_count)
      assert.is_same({}, prov.repair_operations)
      assert.is_same({}, prov.warnings)
    end)
  end)

  describe("Truncate", function()
    it("should return string as-is when under limit", function()
      local str = "short string"
      local result = Types.Truncate(str, 100)

      assert.is.equal(str, result)
    end)

    it("should truncate string over limit", function()
      local str = "this is a very long string that should be truncated"
      local result = Types.Truncate(str, 20, "...")

      assert.is.equal("this is a very lo...", result)
      assert.is_true(#result <= 20)
    end)

    it("should handle nil string", function()
      local result = Types.Truncate(nil, 100)

      assert.is_nil(result)
    end)

    it("should handle empty string", function()
      local result = Types.Truncate("", 100)

      assert.is.equal("", result)
    end)

    it("should use default suffix", function()
      local str = "this is a very long string that should be truncated"
      local result = Types.Truncate(str, 20)

      assert.is.equal("this is a very lo...", result)
    end)
  end)
end)
