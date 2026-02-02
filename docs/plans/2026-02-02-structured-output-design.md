# Structured Output Design for dslua

**Status:** Design Complete ✅
**Date:** 2026-02-02
**Author:** dslua Framework Team
**Version:** 1.0

## Overview

This document specifies the design for a **comprehensive structured output framework** for dslua, providing JSON schema validation, retry with feedback, safe repair, and template-based prompting strategies. The framework enables reliable structured LLM output through a decorator pattern that wraps any module.

## Design Principles

1. **Bounded & Observable** - Strict max retries, timeouts, explicit errors
2. **Safe Repair** - Syntactic fixes only, no semantic invention
3. **LLM-Aligned** - Draft 7 subset, retry prompts optimized for correction
4. **Composable** - Decorator pattern, zero module coupling
5. **Ergonomic** - Convenience wrappers for common cases

---

## Table of Contents

1. [Architecture](#1-architecture)
2. [Core Components](#2-core-components)
3. [ResultEnvelope & Error Model](#3-resultenvelope--error-model)
4. [Validator Keywords](#4-validator-supported-keywords)
5. [Retry Prompt Specification](#5-retry-prompt--feedback-specification)
6. [Template Strategies](#6-template-strategy-interface--mode-gating)
7. [Configuration Schema](#7-configuration-object-schema)
8. [Module Interface Contract](#8-module-interface-contract)
9. [Integration Examples](#9-concrete-integration-examples)

---

## 1. Architecture

The Structured Output framework follows a **three-stage pipeline architecture**:

### Stage 1: Response Acquisition

```
Raw LLM Response
  ↓
Template Strategies (if mode="template")
  ↓ Few-shot → Instructional → Pattern Extraction
JSON Candidate
```

**Template Modes:**
- **Structured mode** (default): No templates, pure JSON
- **Template mode**: Auto-select strategy based on schema
- **Freeform mode**: Pass-through with optional JSON salvage

### Stage 2: Validation & Repair

```
JSON Candidate
  ↓
Attempt 0: Strict Parse + Strict Schema Validation
  ↓ (if failure)
Attempts 1-N: Retry with Structured Feedback (max_retries=2)
  ↓ (if still failing)
Repair Phase: Safe Syntactic Fixes
  ↓
Validated JSON OR Structured Error
```

**Retry Hierarchy:**
1. Retries precede repair (non-negotiable)
2. Retries use low temperature (0-0.1) for determinism
3. Repair is non-semantic only (no invented data)

### Stage 3: Result Envelope

```
Success Case: ResultEnvelope
  - data (parsed JSON)
  - provenance (strict/repaired/retried)
  - debug (opt-in)

Failure Case: ResultEnvelope
  - error (code, message, stage, diagnostics)
  - context (last output, retry count, schema_id)
```

---

## 2. Core Components

### Component Overview

```
Schema Module (dslua.structured.schema)
  ↓ Defines Lua DSL + JSON schema normalization
Validator Module (dslua.structured.validator)
  ↓ Minimal Draft 7 validator + extension hooks
StructuredOutput Decorator (dslua.structured.decorator)
  ↓ Retry policy, repair rules, mode-gating
StructuredPredict Module (dslua.modules.structured_predict)
  Convenience façade (Predict + StructuredOutput)
```

### 2.1 Schema Module

**Location:** `dslua/structured/schema.lua`

**Responsibilities:**
- Define Lua table DSL for Draft 7 schemas
- Normalize both Lua DSL and external JSON schemas
- Validate schema structure itself
- Provide builder methods for convenience

**Exports:**
```lua
Schema.Object(properties, options)
Schema.Array(items_schema, options)
Schema.String(constraints)
Schema.Number(constraints)
Schema.Boolean()
Schema.Null()
```

**Design Notes:**
- Canonical representation remains plain Lua table
- Builder methods are thin sugar only
- Fail fast if schema is invalid

### 2.2 Validator Module

**Location:** `dslua/structured/validator.lua`

**Responsibilities:**
- Validate Lua tables against Draft 7 subset schemas
- Registry-based extension hooks
- Structured error reporting with JSON Pointer paths
- Deterministic, fail-fast validation

**Interface:**
```lua
Validator.validate(data, schema) -> result
result = {
  ok = true|false,
  errors = {
    {path = "/user/age", keyword = "type", expected = "number", actual = "string"}
  }
}

Validator.register(keyword, handler_fn)
```

**Design Notes:**
- Stateless (no global schema state)
- Unknown keywords = error (not silent no-op)
- Registry only stores keyword handlers
- Evaluation order is deterministic (documented per keyword)

### 2.3 StructuredOutput Decorator

**Location:** `dslua/structured/decorator.lua`

**Responsibilities:**
- Wrap any Module with structured output pipeline
- Implement retry → repair → error strategy
- Mode-gating for template strategies
- Return enhanced ResultEnvelope

**Interface:**
```lua
StructuredOutput.new(module, schema, opts) -> enhanced_module

enhanced_module:Process(ctx, input) -> ResultEnvelope
```

**What it does NOT do:**
- Define schemas (Schema module's job)
- Validate schemas (Validator module's job)
- Parse JSON deeply (dkjson's job)

### 2.4 StructuredPredict Module

**Location:** `dslua/modules/structured_predict.lua`

**Responsibilities:**
- Convenience façade for common use cases
- Combines Predict + StructuredOutput

**Interface:**
```lua
StructuredPredict.new(schema, opts) -> module
```

**Implementation:**
```lua
local Predict = require("dslua.modules.predict")
local StructuredOutput = require("dslua.structured.decorator")

function StructuredPredict.new(schema, opts)
  local base = Predict.new(opts.signature)
  local structured = StructuredOutput.new(base, schema, opts)
  return structured
end
```

---

## 3. ResultEnvelope & Error Model

All structured operations return a **ResultEnvelope** data structure.

### 3.1 Success Case

```lua
{
  -- User-facing results
  success = true,
  data = <parsed JSON as Lua table>,

  -- Provenance metadata
  provenance = {
    source = "strict" | "repaired" | "retried",
    attempt_count = 0-2,
    repair_operations = {"markdown_removed", "trailing_commas_fixed"},
    warnings = {}  -- non-fatal issues
  },

  -- Debug (only if debug_enabled=true)
  debug = {
    raw_response = "<original LLM output>",
    validation_time_ms = 45,
    retry_history = {}
  } | nil
}
```

**Usage:**
```lua
if envelope.success then
  local data = envelope.data
  local source = envelope.provenance.source
  if source == "repaired" then
    -- Log salvage occurred
  end
else
  local err = envelope.error
  -- Handle error
end
```

### 3.2 Failure Case

```lua
{
  success = false,
  error = {
    code = "ERR_JSON_PARSE" | "ERR_SCHEMA_VALIDATION" | "ERR_MAX_RETRIES" |
           "ERR_RETRY_UNSUPPORTED" | "ERR_SCHEMA_INVALID" | "ERR_UNSUPPORTED_KEYWORD" |
           "ERR_TIMEOUT" | "ERR_INVALID_OPTION",
    message = "Human-readable summary",
    stage = "parse" | "validate" | "repair",
    recoverable = true|false,

    -- Diagnostics
    validation_errors = {
      {path = "/user/age", expected = "number", actual = "string"}
    } | nil,

    parse_error = "Unexpected token at position 42" | nil,

    -- Context
    last_raw_output = "<truncated if large>",
    retry_count = 2,
    schema_id = "user_profile_v1"
  }
}
```

### 3.3 Design Principles

1. **User checks `success` first**
2. **`data` only present on success**
3. **`error` only present on failure**
4. **Debug info opt-in** (`debug_enabled` flag)

### 3.4 Error Taxonomy

**Stable Error Codes:**
- `ERR_JSON_PARSE` - JSON parsing failed (recoverable)
- `ERR_SCHEMA_VALIDATION` - Schema validation failed (recoverable)
- `ERR_MAX_RETRIES` - Retries exhausted without success (recoverable)
- `ERR_RETRY_UNSUPPORTED` - Retries requested but module doesn't expose prompt (not recoverable)
- `ERR_SCHEMA_INVALID` - Schema itself is invalid (not recoverable)
- `ERR_UNSUPPORTED_KEYWORD` - Schema uses unsupported keyword (not recoverable)
- `ERR_TIMEOUT` - Operation exceeded deadline (not recoverable)
- `ERR_INVALID_OPTION` - Invalid configuration option (not recoverable)

### 3.5 Path Format

**All paths use JSON Pointer format (RFC 6901):**
- `/user/age` - object property
- `/users/2/email` - array index
- `/` - root

**Escaping:**
- `~1` for `/` character in key names
- `~0` for `~` character in key names

**Normalization:**
- Consistent across all error messages
- No Lua-style indexing (`user.age`)
- No mixed formats

---

## 4. Validator Supported Keywords

The validator implements an **LLM-safe subset of JSON Schema Draft 7** (~20% of full spec, ~90% of practical value).

### 4.1 Core Type Keywords (Required)

- `type` - string, number, integer, boolean, object, array, null
- `enum` - Fixed set of allowed values
- `const` - Single allowed value

**Integer Semantics:**
- `integer` = number with no fractional part
- `1.0` allowed (integer value as number type)
- `"1"` not allowed (string, not number)

### 4.2 Object Keywords

- `properties` - Property definitions
- `required` - Array of required property names
- `additionalProperties` - true/false/schema (default: `false` for strictness)
- `minProperties` / `maxProperties` - Property count constraints

### 4.3 Array Keywords

- `items` - Schema for array items (single schema only, no tuple validation)
- `minItems` / `maxItems` - Array length constraints
- `uniqueItems` - Boolean (optional for v1)

### 4.4 String Keywords

- `minLength` / `maxLength` - Length constraints
- `pattern` - Regex pattern (**Lua pattern syntax**, not PCRE)

### 4.5 Numeric Keywords

- `minimum` / `maximum` - Inclusive bounds
- `exclusiveMinimum` / `exclusiveMaximum` - Boolean flags (Draft 7 style)

### 4.6 Composition Keywords (Optional)

- `oneOf` - Exactly one must match (useful for discriminated unions)
- `allOf` - All must match (simple merge, no complex interaction)
- `anyOf` - At least one must match (optional, can add later)

**Composition Rules:**
- `oneOf`: Exactly one schema matches (zero or >1 = error)
- `allOf`: Validate sequentially, no schema rewriting
- Simple evaluation order for deterministic errors

### 4.7 Explicitly NOT Supported (v1)

- ❌ `$ref`, `$defs` - No references/schemas (keep it flat)
- ❌ `if/then/else` - Too complex for LLM outputs
- ❌ `patternProperties` - Rarely needed, complex validation
- ❌ `dependentSchemas` - Advanced, low value
- ❌ `contains` - Array validation edge case
- ❌ Custom vocabularies (Draft 2020-12)

### 4.8 Validation Semantics

**Core Rules:**
1. **Fail fast** - First error stops validation
2. **No coercion** - Types must match exactly
3. **No implicit defaults** - Missing optional fields stay missing
4. **Unknown keywords = error** - Not silent no-ops

**Evaluation Order (for objects):**
1. type check
2. required
3. properties
4. additionalProperties
5. min/maxProperties

**Deterministic error reporting** supports retry feedback.

---

## 5. Retry Prompt & Feedback Specification

When validation fails, the retry prompt provides **structured, actionable feedback** to help the LLM correct its output.

### 5.1 Retry Prompt Template

```
Your previous response was invalid. Please fix and return valid JSON only.

[ERROR DETAILS]
Validation failed at stage: {stage}

{validation_errors_block}

{parse_error_block}

[REQUIRED OUTPUT FORMAT]
Return ONLY valid JSON. No markdown. No commentary. No explanation.
Do not include the schema in your output.
Output must be only the JSON result.

Return a single JSON object or array that conforms to the schema.

[SCHEMA]
{schema_json_or_summary}

[ORIGINAL REQUEST]
{original_prompt}

Try again:
```

### 5.2 Error Blocks

**Validation Errors Block** (if schema validation failed):
```
Schema Validation Errors:
- Path: /user/age
  Expected: number
  Got: "twenty-two"
  Error: Type mismatch

- Path: /user/email
  Expected: string matching pattern: ^[^@]+@[^@]+\.[^@]+$
  Got: "invalid-email"
  Error: Pattern mismatch

Missing required property: /user/id
```

**Parse Error Block** (if JSON parsing failed):
```
JSON Parse Error:
Unexpected token at position 42
Expected: "}" or ","
Got: "name"

First 100 characters:
..."name": "Alice" "age": 30}...
                  ↑ here

Last 100 characters:
..."name": "Alice" "age": 30}...
                                 ↑ missing closing brace
```

### 5.3 Feedback Generation Rules

1. **Exact paths** - Use JSON Pointer format (`/user/age`)
2. **Specific values** - Show both expected and actual
3. **Human-readable** - Explain what went wrong
4. **Ordered** - First error first (fail-fast)
5. **Bounded** - Max 10 validation errors (avoid overwhelming)
6. **No contradictions** - Don't cascade errors (e.g., don't report pattern if type failed)
7. **Highlight missing required fields** - First-class error message

### 5.4 Retry Parameters

**Configuration:**
- `max_retries = 2` (default, configurable)
- `retry_temperature = 0` (or very low, e.g., 0.1)
- `include_raw_output = first 200 chars` (for context)
- `include_schema = always` (re-state requirements)

**Temperature Strategy:**
- **Attempt 0**: Use user's original temperature
- **Retries (1, 2)**: Force low temperature (0-0.1) for deterministic corrections

**Schema Inclusion:**
- Small schemas (< 500 chars): Include full schema
- Large schemas: Include summary (required fields, types, enums/patterns)

### 5.5 Optional Minimal Example

For stubborn models, add a tiny generic example:

```
Example output shape (not your answer):
{"field1":"...", "field2":123}
```

---

## 6. Template Strategy Interface & Mode-Gating

Template strategies produce **JSON candidates** before validation. They're **explicitly optional** and **mode-gated**.

### 6.1 Three Template Modes

**Structured Mode** (default, no templates):
```lua
local output = StructuredOutput.new(module, schema, {
  mode = "structured"  -- Pure JSON, no template strategies
})
```

**Template Mode** (auto-select strategy):
```lua
local output = StructuredOutput.new(module, schema, {
  mode = "template",  -- Enable template strategies
  strategy = "auto"    -- Auto-select based on schema
})
```

**Freeform Mode** (pass-through):
```lua
local output = StructuredOutput.new(module, schema, {
  mode = "freeform"  -- Minimal validation, optional JSON salvage
})
```

### 6.2 Strategy Selection Decision Table

| Schema Characteristics | Selected Strategy | Rationale |
|------------------------|-------------------|-----------|
| Flat + ≤5 fields | Instructional | Simple format, deterministic parsing |
| Nested objects/arrays | Few-shot | LLM learns structure by imitation |
| Has enums/const | Few-shot | Shows allowed values |
| Has pattern constraints | Few-shot | Examples demonstrate patterns |
| Freeform input text | Pattern extraction | Last-resort salvage |
| Token budget < 500 | Instructional | Few-shot too expensive |

### 6.3 Strategy Interfaces

**Few-Shot Strategy:**
```lua
FewShotStrategy.generate(schema, examples) -> prompt_addition
```
- Adds 1-3 examples before user request
- Examples use **placeholder tokens** (`"<string>"`, `123`) not realistic values
- Format: `Input: [task]\nOutput: [example JSON]\n\n`

**Instructional Strategy:**
```lua
InstructionalStrategy.generate(schema) -> prompt_addition
```
- Adds format instructions
- For flat schemas only
- Values must be **JSON-escaped**
- Arrays/objects as valid JSON on right-hand side

**Example:**
```
Name: "<string>"
Age: <number>
Tags: ["<string>", "<string>"]
Profile: {"key": "<value>"}
```

**JSON Salvage Strategy** (renamed from pattern extraction):
```lua
JsonSalvageStrategy.extract(text, schema) -> json_candidate
```
- Post-processing step (not prompt modification)
- Extracts largest `{...}` or `[...]` block
- Applies safe syntactic repairs
- Marks result as `lossy=true` in provenance
- **Non-semantic only** - no field value extraction from prose

### 6.4 Strategy Escalation (Template Mode)

**Escalation depends on initially selected strategy:**

- If selected = **Instructional** → retry instructional (tighten instructions), optional few-shot if budget allows
- If selected = **Few-shot** → retry few-shot (stronger examples), optional instructional only if schema flat and budget constrained
- **JSON salvage** only in **freeform mode** or explicit opt-in

### 6.5 Freeform Mode Definition

**Freeform mode = lossy by design:**
- Does not enforce full schema validation
- Attempts basic JSON parse + top-level type check
- `allow_lossy = true` automatically
- `enable_json_salvage = true` automatically
- `max_retries = 0` (no retries in freeform)
- `enable_repair = true` (still does syntactic repair)

**Use case:** Last-resort data recovery from unstructured outputs.

---

## 7. Configuration Object Schema

All structured output behavior controlled via **StructuredOutputOptions**.

### 7.1 Full Configuration Schema

```lua
{
  -- === Mode Selection ===
  mode = "structured" | "template" | "freeform",  -- Required

  -- === Schema ===
  -- schema passed as separate argument (not in opts)
  -- opts.schema deprecated/disallowed to avoid duplication

  -- === Retry Policy ===
  max_retries = 2,                    -- Default: 2
  retry_temperature = 0,              -- Default: 0 (deterministic)
  retry_top_p = nil,                 -- Inherit from original

  -- === Template Strategy (mode="template" only) ===
  strategy = "auto" | "few-shot" | "instructional",
  max_examples = 3,                  -- Few-shot max examples
  token_budget_threshold = 500,      -- Switch to instructional if under

  -- === Repair Options ===
  enable_repair = true,              -- Default: true
  repair_markdown_fences = true,
  repair_trailing_commas = true,
  repair_normalize_quotes = true,

  -- === Lossy Salvage (mode="freeform" or explicit opt-in) ===
  allow_lossy = false,               -- Default: false (except freeform)
  enable_json_salvage = false,       -- Default: false (except freeform)
  require_top_level = "object" | "array" | nil,  -- For salvage

  -- === Debug Options ===
  debug_enabled = false,             -- Include debug block in envelope
  include_raw_response = true,       -- In debug block
  include_retry_history = true,      -- In debug block

  -- === Truncation Limits ===
  max_raw_output_chars = 2000,       -- Debug truncation
  max_error_output_chars = 500,      -- Error truncation

  -- === Timeout ===
  timeout_ms = 30000,                -- 30s default, entire pipeline

  -- === Advanced (rarely needed, v1 fixed) ===
  error_collection = "first" | "up_to_10",  -- Default: "first"
  unknown_keywords = "error",        -- v1: fixed to "error" (not configurable)
}
```

### 7.2 Mode-Specific Defaults

**Structured mode** (default):
```lua
{
  mode = "structured",
  max_retries = 2,
  enable_repair = true,
  allow_lossy = false
}
```

**Template mode:**
```lua
{
  mode = "template",
  strategy = "auto",
  max_examples = 3,
  max_retries = 2,
  enable_repair = true
}
```

**Freeform mode:**
```lua
{
  mode = "freeform",
  allow_lossy = true,              -- Implied by freeform
  enable_json_salvage = true,      -- Implied by freeform
  max_retries = 0,                  -- No retries in freeform
  enable_repair = true              -- Still do syntactic repair
}
```

### 7.3 Validation Rules

- `mode` required
- `schema` required for structured/template modes (passed as separate arg)
- `allow_lossy` only allowed in freeform mode or if explicitly enabled
- `strategy="auto"` triggers decision table
- Invalid options throw `ERR_INVALID_OPTION`

### 7.4 Defaults Philosophy

- **Safe by default** (strict validation, retries enabled)
- **No lossy operations** unless explicit (except freeform)
- **Debug off** in production (opt-in)
- **Bounded operations** (max retries, timeouts, truncation)

---

## 8. Module Interface Contract

The StructuredOutput decorator wraps any Module, requiring a **minimal interface contract**.

### 8.1 Required Module Interface

```lua
{
  -- Must implement Process method
  Process = function(ctx, input) -> response
}
```

### 8.2 Response Interface

**Required:**
```lua
response = {
  content = "<string>"  -- Raw LLM output text (required)
}
```

**Optional (highly recommended for safe retries):**
```lua
response = {
  content = "<string>",

  -- Optional but highly recommended:
  prompt = "<string>",         -- Exact prompt that produced response.content
  llm_opts = {                 -- LLM params used for this attempt
    temperature = 0.7,
    top_p = 0.9
  },
  model = "gpt-4",             -- Optional: Model identifier
}
```

**Optional metadata fields:**
```lua
response = {
  -- ... required/opt retry fields above ...

  -- Modules may attach extra metadata (decorator ignores these):
  usage = {total_tokens = 42},
  timing = {latency_ms = 150},
  reasoning = ["step1", "step2"],  -- ChainOfThought
  trace = {{...}},                    -- ReAct tool calls
  -- etc.
}
```

### 8.3 Context Interface

```lua
ctx = {
  -- Required:
  LLM = function() -> llm_provider,

  -- LLM provider contract:
  -- Complete = function(llm, ctx, prompt, opts) -> response

  -- Optional (for timeout/cancellation):
  deadline_ms = 1728492000000,     -- Unix timestamp (ms) or nil
  is_cancelled = function() -> boolean,
  time_remaining_ms = function() -> number or nil
}
```

**LLM Provider Contract:**
- `opts` can override temperature/top_p on retries
- Returns response shape: `{ content = "...", ... }`

### 8.4 Signature Interface (Optional)

```lua
signature = {
  InputFields = function() -> {Field, ...},
  OutputFields = function() -> {Field, ...}
}

field = {
  name = "<string>",
  type = "<string>"  -- Optional: for schema generation hints
}
```

**Signature Integration:**
- If `schema` passed explicitly → Signature ignored
- If `schema == nil` + signature present → auto-generate schema (structured/template modes only)
- Freeform mode never requires signature

### 8.5 Assumptions Decorator Makes

1. **Response has content field** - Raw text output to parse
2. **Original prompt accessible** - For retries (captured from `response.prompt`)
3. **LLM-level retries** - Retries call `ctx:LLM():Complete()` directly, **NOT** `module:Process()`
4. **Ctx has LLM** - Available for retry calls
5. **No module re-execution** - Never re-run module logic (would duplicate side effects)

### 8.6 Retry Behavior

**Safe Retry Strategy:**
- If `response.prompt` exists → **LLM-level retries**
  - Calls `ctx:LLM():Complete(retry_prompt, retry_opts)` directly
  - Bypasses module logic entirely
  - Safe for modules with side effects (ReAct tool calls, etc.)

- If `response.prompt` missing → **No retries**
  - Return `ERR_RETRY_UNSUPPORTED` (recoverable=false)
  - Message: "Retries require response.prompt; module did not provide it"

**Retry Prompt Construction:**
```
retry_prompt = RetryTemplate(
  error_details,
  schema,
  response.prompt,     -- Used as input to template
  last_output_snippets
)
```

### 8.7 Decorator Contract

**Input:**
```lua
StructuredOutput.new(module, schema, opts) -> enhanced_module
```

**Output:**
```lua
enhanced_module:Process(ctx, input) -> ResultEnvelope
```

**Breaking Change:**
- Decorated `Process()` returns `ResultEnvelope`, not original `response`
- Optional `unwrap()` helper:
  ```lua
  envelope:unwrap() -> {content = json_string, provenance = provenance_table}
  ```

### 8.8 Explicit Guarantees

1. **Attempt 0 prompt capture** - Captured from `response.prompt` before first validation attempt
2. **Repair scope** - Only applies to JSON candidate, never touches prompt or schema
3. **No module re-execution** - Retries never call `module:Process()` again
4. **Side effects preserved** - Tool calls, state changes never duplicated

---

## 9. Concrete Integration Examples

### 9.1 Example: Predict Module

```lua
local Predict = require("dslua.modules.predict")

function Predict:Process(ctx, input)
  local llm = ctx:LLM() or self:LLM()
  local prompt = self:_buildPrompt(input)

  -- Example response: { content = "{\"name\": \"Alice\", \"age\": 30}",
  --                  usage = {total_tokens = 42},
  --                  model = "llama3.2" }
  local response = llm:Complete(ctx, prompt, self._llm_opts or {})

  -- Expose for safe LLM-level retries
  response.prompt = prompt
  response.llm_opts = self._llm_opts or {}

  return response
end

-- Wrapped with StructuredOutput:
local module = Predict.new(signature)
local structured = StructuredOutput.new(module, user_schema, {
  max_retries = 2
})

local ctx = Context.new({llm = ollama_llm})
local envelope = structured:Process(ctx, {question = "Generate user profile"})
```

### 9.2 Example: ChainOfThought Module

```lua
function ChainOfThought:Process(ctx, input)
  local llm = ctx:LLM() or self:LLM()
  local prompt = self:_buildReasoningPrompt(input)
  local response = llm:Complete(ctx, prompt, self._llm_opts or {})

  local reasoning = self:_extractReasoning(response.content)
  local final_answer = reasoning.answer

  -- CRITICAL: Set content to final answer for validation
  -- (not full reasoning output)
  response.content = final_answer
  response.prompt = prompt
  response.llm_opts = self._llm_opts or {}
  response.reasoning = reasoning.steps  -- Extra metadata

  return response
end

-- Wrapped - safe to retry the reasoning step
local cot = ChainOfThought.new(signature)
local structured = StructuredOutput.new(cot, schema, {
  max_retries = 2
})
```

### 9.3 Example: ReAct Module (Multi-step with Tool Calls)

```lua
function ReAct:Process(ctx, input)
  local llm = ctx:LLM() or self:LLM()
  local trace = {}
  local prompt = nil

  for iteration = 1, self._max_iterations do
    prompt = self:_buildStepPrompt(trace, input)
    local response = llm:Complete(ctx, prompt, self._llm_opts or {})

    -- Framework-specific: structured tool_call field indicates tool request
    if response.tool_call then
      local tool_result = self:_executeTool(response.tool_call)
      table.insert(trace, {tool = response.tool_call, result = tool_result})
    else
      -- Final answer - response.prompt MUST be exact prompt for this response.content
      response.prompt = prompt
      response.llm_opts = self._llm_opts or {}
      response.trace = trace
      return response
    end
  end

  -- Max iterations exhausted - return deterministic error
  return {
    content = "",
    prompt = prompt,
    llm_opts = self._llm_opts or {},
    trace = trace,
    error = "ERR_MAX_ITERATIONS"
  }
end

-- Wrapped - safe to retry final step without re-running tools
local react = ReAct.new(signature, {tool_registry = registry})
local structured = StructuredOutput.new(react, schema, {
  max_retries = 2
})
```

### 9.4 Example: Module without prompt (ERR_RETRY_UNSUPPORTED)

```lua
-- Custom module that doesn't expose prompt
local CustomModule = {}
function CustomModule:Process(ctx, input)
  -- Makes internal LLM calls, doesn't expose prompt
  local response = internal_llm:Complete(...)
  -- NO response.prompt set
  return response  -- { content = "..." }
end

-- Attempting to wrap with retries fails
local structured = StructuredOutput.new(CustomModule, schema, {
  max_retries = 2  -- Will cause ERR_RETRY_UNSUPPORTED
})

structured:Process(ctx, input)
-- → Returns ResultEnvelope with ERR_RETRY_UNSUPPORTED:
-- "Retries require response.prompt; module did not provide it"
```

---

## Implementation Phases

### Phase 1: Core Infrastructure
- [ ] Schema module (Lua DSL + normalization)
- [ ] Validator module (Draft 7 subset)
- [ ] ResultEnvelope type definitions
- [ ] Error taxonomy

### Phase 2: Decorator & Pipeline
- [ ] StructuredOutput decorator
- [ ] Retry logic with feedback
- [ ] Safe repair operations
- [ ] Mode-gating implementation

### Phase 3: Template Strategies
- [ ] Few-shot strategy
- [ ] Instructional strategy
- [ ] JSON salvage strategy
- [ ] Decision table logic

### Phase 4: Integration & Testing
- [ ] StructuredPredict convenience module
- [ ] Ollama integration tests
- [ ] Module wrapping tests (Predict, CoT, ReAct)
- [ ] End-to-end validation tests

### Phase 5: Documentation
- [ ] API documentation
- [ ] Usage examples
- [ ] Schema guide
- [ ] Error handling guide

---

## Appendix: Design Decisions

### Why Decorator Pattern?

- **Zero coupling** - No knowledge of module internals
- **Universal** - Works with any current/future module
- **Composable** - Decorators can stack
- **Policy isolation** - Structured output logic in one place

### Why LLM-Level Retries?

- **Safe for side effects** - Tool calls never duplicated
- **Deterministic** - Same prompt + low temperature = reproducible
- **Efficient** - No re-execution of complex multi-step logic

### Why Minimal Validator?

- **Correctness** - Full Draft 7 is huge and error-prone
- **LLM-aligned** - Subset optimized for LLM behavior
- **Maintainable** - Small codebase, clear semantics
- **Extensible** - Registry for custom validators

### Why Draft 7 (not 2020-12)?

- **Universal support** - All major validators support it
- **LLM-friendly** - Models trained on Draft 7-style schemas
- **Stable** - No breaking changes expected
- **Sufficient** - Has all features needed for LLM output

### Why Fail-Fast Validation?

- **Deterministic** - Same error every time
- **Clear feedback** - First error is most actionable
- **Bounded** - Prevents error list explosion
- **Retry-optimized** - Focused corrections work better

---

## Glossary

- **Decorator** - Wrapper that adds behavior without modifying original
- **LLM-safe subset** - Minimal schema features that LLMs handle reliably
- **Provenance** - Metadata about how result was produced (strict/repaired/retried)
- **Safe repair** - Syntactic fixes only, no semantic invention
- **Structured output** - LLM response conforming to JSON schema
- **Template strategy** - Prompt modification technique to encourage JSON output

---

**End of Design Document**
