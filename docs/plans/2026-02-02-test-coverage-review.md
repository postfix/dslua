# Structured Output Test Coverage Review

**Date**: 2026-02-02
**Review Type**: Comprehensive test coverage analysis
**Status**: ✅ Good coverage with specific gaps identified

## Executive Summary

| Metric | Value | Assessment |
|--------|-------|------------|
| Total Tests | 157 | Good |
| Implementation Lines | 2,325 | - |
| Lines per Test | 14.8 | ✅ Good ratio |
| Test Pass Rate | 100% | ✅ All passing |
| Integration Tests | 3 passing | ✅ Ollama validated |

**Overall Grade**: ✅ **Good** (B+) - Strong foundation with specific gaps in critical paths

---

## Module-by-Module Coverage

| Module | Lines | Tests | L/T Ratio | Coverage |
|--------|-------|-------|-----------|----------|
| types | 164 | 17 | 9.6 | ✅ Excellent |
| schema | 266 | 20 | 13.3 | ✅ Good |
| validator | 560 | 28 | 20.0 | ⚠️ Fair |
| decorator | 354 | 11 | 32.2 | ⚠️ Low |
| fewshot | 270 | 19 | 14.2 | ✅ Good |
| instructional | 247 | 23 | 10.7 | ✅ Good |
| json_salvage | 295 | 21 | 14.0 | ✅ Good |
| selector | 169 | 18 | 9.4 | ✅ Excellent |
| **Total** | **2,325** | **157** | **14.8** | **✅ Good** |

---

## Critical Gaps (High Priority)

### 1. ⚠️ Decorator Timeout Handling
**Location**: `decorator.lua:53-58`
```lua
if deadline_ms and (os.time() * 1000 > deadline_ms) then
  return Types.ErrorResult(Types.ErrorCodes.TIMEOUT, ...)
end
```
**Impact**: Production safety - untested code path in production
**Risk**: Medium - Timeout critical for SLA compliance

### 2. ⚠️ Provenance Tracking Details
**Missing Tests**:
- `source = "strict"` for valid JSON
- `source = "repaired"` when repairs applied
- `source = "retried"` with attempt_count
- `repair_operations` list verification

**Impact**: Debugging and observability
**Risk**: Low - Provenance important for diagnostics

### 3. ⚠️ Retry Prompt Format
**Missing Tests**:
- `_build_retry_prompt()` output format
- Error details inclusion
- Schema inclusion
- Validation error formatting

**Impact**: Retry effectiveness
**Risk**: Medium - Critical for self-correction

### 4. ⚠️ Error Context Structure
**Missing Tests**:
- `last_raw_output` truncation
- `retry_count` accuracy
- `diagnostics` structure
- `context` table fields

**Impact**: Error diagnostics
**Risk**: Medium - Important for debugging

### 5. ⚠️ Repair Operations Tracking
**Missing Tests**:
- `repair_operations` list population
- Multiple repair types combination
- Repair operation naming

**Impact**: Provenance accuracy
**Risk**: Low - Useful for debugging

---

## Recommended Actions

### Immediate (This Week) - High Priority

#### Action 1: Add Decorator Timeout Tests
```lua
it("should return timeout error when deadline exceeded", function()
  local past_deadline = os.time() * 1000 - 1000  -- 1 second ago
  local ctx = Context.new({
    llm = mock_llm,
    deadline_ms = past_deadline
  })

  local envelope = decorated:Process(ctx, {})

  assert.is_false(envelope.success)
  assert.is_equal(Types.ErrorCodes.TIMEOUT, envelope.error.code)
end)

it("should not timeout when deadline not exceeded", function()
  local future_deadline = os.time() * 1000 + 60000  -- 1 minute from now
  local ctx = Context.new({
    llm = mock_llm,
    deadline_ms = future_deadline
  })

  local envelope = decorated:Process(ctx, {})

  assert.is_true(envelope.success)
end)
```

#### Action 2: Add Provenance Tracking Tests
```lua
it("should set provenance.source to strict for valid JSON", function()
  local envelope = decorated:Process(ctx, {question = "Generate user"})

  assert.is_equal("strict", envelope.provenance.source)
  assert.is_equal(0, envelope.provenance.attempt_count)
end)

it("should set provenance.source to repaired when repairs applied", function()
  -- Response with markdown fence that needs repair
  local envelope = decorated:Process(ctx, {})

  assert.is_equal("repaired", envelope.provenance.source)
  assert.is_true(#envelope.provenance.repair_operations > 0)
end)

it("should set provenance.source to retried after successful retry", function()
  local attempt = 0
  local mock_module = {
    Process = function(self, ctx, input)
      attempt = attempt + 1
      return {
        content = attempt == 1 and "invalid" else '{"valid": true}',
        prompt = "Generate"
      }
    end
  }

  local envelope = decorated:Process(ctx, {})

  assert.is_equal("retried", envelope.provenance.source)
  assert.is_true(envelope.provenance.attempt_count >= 1)
end)
```

#### Action 3: Add Retry Prompt Verification Tests
```lua
it("should include error details in retry prompt", function()
  -- Capture retry prompt
  local retry_prompts = {}
  local mock_llm = {
    Complete = function(self, ctx, prompt, opts)
      table.insert(retry_prompts, prompt)
      return {content = '{"valid": true}'}
    end
  }

  -- Trigger retry
  local envelope = decorated:Process(ctx, {})

  -- Verify retry prompt structure
  local retry_prompt = retry_prompts[1]
  assert.is_true(string.find(retry_prompt, "ERROR DETAILS") ~= nil)
  assert.is_true(string.find(retry_prompt, "Validation failed") ~= nil)
end)

it("should include schema in retry prompt", function()
  local retry_prompts = {}
  -- ... capture prompt

  local retry_prompt = retry_prompts[1]
  assert.is_true(string.find(retry_prompt, "[SCHEMA]") ~= nil)
  assert.is_true(string.find(retry_prompt, "type") ~= nil)  -- Has schema content
end)

it("should format validation errors correctly", function()
  local retry_prompts = {}
  -- ... trigger validation error

  local retry_prompt = retry_prompts[1]
  assert.is_true(string.find(retry_prompt, "Path:") ~= nil)
  assert.is_true(string.find(retry_prompt, "Expected:") ~= nil)
  assert.is_true(string.find(retry_prompt, "Got:") ~= nil)
end)
```

### Short-term (This Sprint) - Medium Priority

#### Action 4: Add Error Context Tests
```lua
it("should truncate last_raw_output in error context", function()
  local long_content = string.rep("x", 1000)
  local envelope = decorated:Process(ctx, {})

  assert.is_not_nil(envelope.context.last_raw_output)
  assert.is_true(#envelope.context.last_raw_output <= 500)  -- Default max
end)

it("should track retry_count accurately", function()
  local envelope = decorated:Process(ctx, {})

  if not envelope.success then
    assert.is_not_nil(envelope.context.retry_count)
  end
end)

it("should include validation errors in diagnostics", function()
  local envelope = decorated:Process(ctx, {})

  if not envelope.success and envelope.error.code == "ERR_SCHEMA_VALIDATION" then
    assert.is_not_nil(envelope.error.diagnostics.validation_errors)
    assert.is_true(#envelope.error.diagnostics.validation_errors > 0)
  end
end)
```

#### Action 5: Add Strategy Integration Tests
```lua
it("should apply few-shot strategy when mode=template", function()
  local decorated = StructuredOutput.new(mock_module, schema, {
    mode = "template",
    strategy = "few-shot"
  })

  -- Verify strategy applied
  local envelope = decorated:Process(ctx, {})
  -- ... assertions
end)

it("should auto-select strategy based on schema", function()
  local decorated = StructuredOutput.new(mock_module, complex_schema, {
    mode = "template",
    strategy = "auto"
  })

  local envelope = decorated:Process(ctx, {})
  -- ... verify appropriate strategy used
end)
```

### Long-term (Next Sprint) - Low Priority

#### Action 6: Add Token Estimation Tests
```lua
it("should estimate tokens for schema", function()
  local schema = Schema.Object({
    name = {type = "string"},
    age = {type = "integer"}
  })

  local tokens = StrategySelector.estimate_tokens(schema)

  assert.is_true(tokens > 0)
  assert.is_true(tokens < 1000)
end)
```

---

## Strengths ✅

1. **Complete Coverage** - All 8 modules have test coverage
2. **Core Functionality** - Main paths well-tested
3. **Edge Cases** - Most boundary conditions covered
4. **Integration Validated** - Ollama tests confirm real-world usage
5. **Consistent Structure** - Test naming and organization consistent
6. **Good Balance** - Mix of unit and integration tests

---

## Weaknesses ⚠️

1. **Decorator Coverage** - 32.2 lines/test (low ratio)
2. **Timeout Logic** - Completely untested
3. **Provenance Details** - Not verified
4. **Retry Prompts** - Format not tested
5. **Error Context** - Structure not validated

---

## Next Steps

### Week 1: Critical Tests
- [ ] Add 3 timeout tests
- [ ] Add 5 provenance tests
- [ ] Add 4 retry prompt tests

### Week 2: Important Tests
- [ ] Add 4 error context tests
- [ ] Add 3 strategy integration tests
- [ ] Run full test suite with coverage tool

### Week 3: Enhancement
- [ ] Consider property-based testing
- [ ] Add performance tests
- [ ] Document all edge case behaviors

---

## Tools to Consider

```bash
# Install busted coverage support
luarocks install busted
luarocks install luacov

# Generate coverage report
busted --coverage
luacov-report
```

---

## Conclusion

The structured output implementation has **good test coverage (157 tests)** with all core functionality validated. However, there are **critical gaps in the decorator module** that should be addressed:

1. **Timeout handling** - Unreachable code path (production safety issue)
2. **Provenance tracking** - Critical for debugging
3. **Retry prompts** - Important for self-correction effectiveness

**Recommendation**: Add the 12 high-priority tests immediately to reach production-ready coverage.

**Current Grade**: B+ (Good)
**Target Grade**: A (Excellent) - After adding high-priority tests

---

**Review Completed By**: Claude Sonnet 4.5
**Next Review Date**: After high-priority tests added
