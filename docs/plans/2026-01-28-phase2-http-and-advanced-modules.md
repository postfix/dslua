# Phase 2: HTTP Integration and Advanced Modules Design

**Date:** 2026-01-28
**Status:** Design Complete
**Goal:** Implement functional HTTP-based LLM providers and advanced reasoning modules

## Overview

Phase 2 transforms dslua from a prototype with mock LLMs into a functional framework with real API integration. We'll implement HTTP client integration for the OpenAI provider, add Anthropic and Gemini providers, and build advanced reasoning modules (ChainOfThought, ReAct, Refine) that leverage working providers.

**Priority:** HTTP integration first → Modules → Additional providers

## Architecture

### Dependency Flow

```
HTTP Client (lua-http) → OpenAI Provider (functional)
    ↓
ChainOfThought Module → ReAct Module → Refine Module
    ↓
Anthropic Provider → Gemini Provider
```

### Key Design Decisions

1. **Vendor Dependencies:** lua-http and dkjson into `deps/` for zero-install setup
2. **Provider Abstraction:** HTTP wrapper in `dslua/llms/http.lua` shared across providers
3. **Parsed Responses:** Providers return Lua tables, not raw JSON strings
4. **Error Classification:** Distinguish HTTP errors from LLM API errors
5. **Prompt Composition:** Modules build prompts by composing field values with templates

---

## Component 1: HTTP Client Layer

### HTTP Client Wrapper (`dslua/llms/http.lua`)

Provides unified interface for all LLM providers with request/response handling.

```lua
local http = require("deps.lua-http.socket")
local dkjson = require("deps.dkjson")

local HttpClient = {}
HttpClient.__index = HttpClient

function HttpClient.new(timeout)
    return setmetatable({
        _timeout = timeout or 30000,
    }, HttpClient)
end

function HttpClient:Post(url, headers, body)
    local request_body = dkjson.encode(body)
    local response_body = {}

    local response, status, response_headers = http.request({
        url = url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_body),
    })

    if status >= 400 then
        error(string.format("HTTP Error %d: %s", status, table.concat(response_body)))
    end

    return dkjson.decode(table.concat(response_body))
end

return HttpClient
```

**Features:**
- Configurable timeout (default 30s)
- Automatic JSON encoding/decoding
- HTTP error detection and reporting
- Lua socket integration via lua-http

### Error Classification (`dslua/llms/errors.lua`)

```lua
local Errors = {}

function Errors.HTTPError(status, message)
    return {
        type = "HTTPError",
        status = status,
        message = message,
    }
end

function Errors.APIError(code, message)
    return {
        type = "APIError",
        code = code,
        message = message,
    }
end

function Errors.RateLimitError(retry_after)
    return {
        type = "RateLimitError",
        retry_after = retry_after,
    }
end

return Errors
```

**Error Types:**
- `HTTPError` - Network/transport layer failures
- `APIError` - LLM provider returned error (invalid request, etc.)
- `RateLimitError` - Rate limit hit with retry_after timestamp

---

## Component 2: OpenAI Provider Enhancement

### Updated OpenAI Implementation

Update `dslua/llms/providers/openai.lua` to use HTTP client:

```lua
local BaseLLM = require("dslua.llms.base")
local HttpClient = require("dslua.llms.http")
local Errors = require("dslua.llms.errors")

local OpenAI = {}
OpenAI.__index = OpenAI
setmetatable(OpenAI, {__index = BaseLLM})

function OpenAI.new(api_key, model, opts)
    opts = opts or {}
    local config = {
        api_key = api_key,
        model = model,
        base_url = opts.base_url or "https://api.openai.com/v1",
        timeout = opts.timeout or 30000,
    }
    local self = BaseLLM.new(config)
    setmetatable(self, OpenAI)
    self._http = HttpClient.new(config.timeout)
    return self
end

function OpenAI:Complete(ctx, prompt, opts)
    opts = opts or {}
    local body = self:_buildRequestBody(prompt, opts)
    local headers = {
        ["Authorization"] = "Bearer " .. self._api_key,
        ["Content-Type"] = "application/json",
    }

    local response, err = self._http:Post(
        self._base_url .. "/chat/completions",
        headers,
        body
    )

    if err then
        error(err)
    end

    return self:_parseResponse(response)
end

function OpenAI:_buildRequestBody(prompt, opts)
    return {
        model = self._model,
        messages = {{role = "user", content = prompt}},
        temperature = opts.temperature or 0.7,
        max_tokens = opts.max_tokens or 1024,
    }
end

function OpenAI:_parseResponse(response)
    if response.error then
        error(Errors.APIError(response.error.code, response.error.message))
    end

    return {
        content = response.choices[1].message.content,
        usage = response.usage,
        model = response.model,
        finish_reason = response.choices[1].finish_reason,
    }
end

return OpenAI
```

**Changes from Phase 1:**
- Adds HttpClient instantiation
- Implements real `Complete()` method (was error stub)
- Parses actual API response structure
- Handles API errors in response

**Testing Strategy:**
- Unit tests with mock HTTP responses
- Integration tests with real API key (opt-in via environment variable)
- Error path tests (rate limits, invalid requests)

---

## Component 3: ChainOfThought Module

### Architecture

```lua
-- dslua/modules/chain_of_thought.lua
local Predict = require("dslua.modules.predict")

local ChainOfThought = {}
ChainOfThought.__index = ChainOfThought
setmetatable(ChainOfThought, {__index = Predict})

function ChainOfThought.new(signature)
    local self = Predict.new(signature)
    setmetatable(self, ChainOfThought)
    return self
end

function ChainOfThought:Process(ctx, input)
    local llm = ctx:LLM() or self:LLM()
    local prompt = self:_buildCOTPrompt(input)
    local response = llm:Complete(ctx, prompt)
    return self:_parseOutput(response)
end

function ChainOfThought:_buildCOTPrompt(input)
    local template = [[
Think step-by-step to answer the following question.

%s

Reasoning: Let's think through this step by step.
Answer:]]

    local input_text = self:_formatInputs(input)
    return string.format(template, input_text)
end

function ChainOfThought:_parseOutput(response)
    local content = response.content

    -- Try to extract structured reasoning and answer
    local reasoning = content:match("Reasoning: (.*)Answer:") or ""
    local answer = content:match("Answer: (.*)") or content

    return {
        reasoning = reasoning:match("Let's think(.*)") or reasoning,
        answer = answer,
        raw = content,
    }
end

return ChainOfThought
```

### Prompt Strategy

**Template:**
```
Think step-by-step to answer the following question.

question: <input field values>

Reasoning: Let's think through this step by step.
Answer:
```

**Features:**
- Explicit "step-by-step" instruction
- Structure markers for parsing (Reasoning:/Answer:)
- Fallback to full response if parsing fails
- Preserves both reasoning trace and final answer

### Output Format

```lua
{
    reasoning = "6 * 7 = 42, so the answer is 42",
    answer = "42",
    raw = "Reasoning: Let's think... Answer: 42"
}
```

---

## Component 4: ReAct Module with Tool Use

### Architecture

```lua
-- dslua/modules/react.lua
local ChainOfThought = require("dslua.modules.chain_of_thought")

local ReAct = {}
ReAct.__index = ReAct
setmetatable(ReAct, {__index = ChainOfThought})

function ReAct.new(signature, opts)
    opts = opts or {}
    local self = ChainOfThought.new(signature)
    setmetatable(self, ReAct)
    self._tools = opts.tools or {}
    self._maxIterations = opts.max_iterations or 10
    return self
end

function ReAct:Process(ctx, input)
    local state = {
        thoughts = {},
        actions = {},
        observations = {},
        input = input,
    }

    for i = 1, self._maxIterations do
        -- Generate thought and action
        local prompt = self:_buildReActPrompt(state, i)
        local response = (ctx:LLM() or self:LLM()):Complete(ctx, prompt)
        local step = self:_parseStep(response.content)

        table.insert(state.thoughts, step.thought)

        if step.action == "finish" then
            state.answer = step.answer
            break
        end

        -- Execute tool
        local tool = self:_findTool(step.action)
        local observation = tool:Execute(step.args)
        table.insert(state.observations, observation)
        table.insert(state.actions, {action = step.action, args = step.args})
    end

    return self:_formatOutput(state)
end

function ReAct:_buildReActPrompt(state, iteration)
    local template = [[
Question: %s

%s

Thought %d:]]

    local history = self:_formatHistory(state)
    local question = self:_formatInputs(state.input)

    return string.format(template, question, history, iteration)
end

function ReAct:_formatHistory(state)
    local parts = {}
    for i, obs in ipairs(state.observations) do
        table.insert(parts, string.format("Observation %d: %s", i, obs))
    end
    return table.concat(parts, "\n")
end

function ReAct:_findTool(name)
    for _, tool in ipairs(self._tools) do
        if tool:Name() == name then
            return tool
        end
    end
    error("Tool not found: " .. name)
end

function ReAct:_parseStep(content)
    -- Parse: Thought: ... Action: tool_name[args]
    local thought = content:match("Thought:%s*(.-)\n") or ""
    local action_line = content:match("Action:%s*(.-)\n") or ""

    local action, args = action_line:match("^(.+)%[(.+)%]$")

    if not action then
        action = "finish"
        args = content:match("Answer:%s*(.+)") or content
    end

    if action == "finish" then
        return {thought = thought, action = "finish", answer = args}
    end

    return {
        thought = thought,
        action = action,
        args = self:_parseArgs(args)
    }
end

function ReAct:_parseArgs(args_str)
    -- Simple parser: tool_name["arg1", "arg2"] or tool_name[key=value]
    -- For now, return as string, tools can parse themselves
    return args_str
end

function ReAct:_formatOutput(state)
    return {
        answer = state.answer,
        thoughts = state.thoughts,
        actions = state.actions,
        observations = state.observations,
        iterations = #state.thoughts,
    }
end

return ReAct
```

### Tool Interface

```lua
-- dslua/tools/base.lua
local Tool = {}
Tool.__index = Tool

function Tool.new(name, config)
    return setmetatable({
        _name = name,
        _description = config.description,
        _func = config.func,
    }, Tool)
end

function Tool:Execute(args)
    return self._func(args)
end

function Tool:Name()
    return self._name
end

function Tool:Description()
    return self._description
end

return Tool
```

### ReAct Prompt Template

```
Question: What is the population of Tokyo?

Thought 1: I need to search for the population of Tokyo.
Action 1: search["population of Tokyo"]
Observation 1: Tokyo has a population of approximately 14 million people.
Thought 2: I have the information needed to answer.
Action 2: finish[The population of Tokyo is approximately 14 million people.]
```

### Output Format

```lua
{
    answer = "The population of Tokyo is approximately 14 million.",
    thoughts = {...},
    actions = {{action = "search", args = "population of Tokyo"}},
    observations = {"Tokyo has a population of..."},
    iterations = 2
}
```

---

## Component 5: Refine Module

### Architecture

```lua
-- dslua/modules/refine.lua
local Predict = require("dslua.modules.predict")

local Refine = {}
Refine.__index = Refine
setmetatable(Refine, {__index = Predict})

function Refine.new(signature, opts)
    opts = opts or {}
    local self = Predict.new(signature)
    setmetatable(self, Refine)
    self._maxIterations = opts.max_iterations or 3
    return self
end

function Refine:Process(ctx, input)
    local llm = ctx:LLM() or self:LLM()
    local current = {content = ""}

    for i = 1, self._maxIterations do
        local prompt = self:_buildRefinePrompt(input, current, i)
        local response = llm:Complete(ctx, prompt)

        if i == 1 then
            current = response
        else
            -- Extract refined answer
            local refined = response.content:match("Refined answer:%s*(.*)")
            current.content = refined or response.content
        end
    end

    return {
        answer = current.content,
        iterations = self._maxIterations
    }
end

function Refine:_buildRefinePrompt(input, previous, iteration)
    if iteration == 1 then
        return string.format("%s\n\nAnswer:", self:_formatInputs(input))
    end

    return string.format([[Original question: %s

Previous answer: %s

Please critique and improve this answer. Focus on:
1. Accuracy - Is the information correct?
2. Completeness - Is anything important missing?
3. Clarity - Is the answer well-structured and easy to understand?

Refined answer:]],
        self:_formatInputs(input),
        previous.content
    )
end

return Refine
```

### Refinement Strategy

**Iteration 1:** Generate initial answer
**Iteration 2+:** Critique and refine previous answer

**Prompt Template:**
```
Original question: <input>

Previous answer: <previous answer>

Please critique and improve this answer. Focus on accuracy, completeness, and clarity.

Refined answer: <improved answer>
```

---

## Component 6: Anthropic Provider

### Implementation

```lua
-- dslua/llms/providers/anthropic.lua
local BaseLLM = require("dslua.llms.base")
local HttpClient = require("dslua.llms.http")

local Anthropic = {}
Anthropic.__index = Anthropic
setmetatable(Anthropic, {__index = BaseLLM})

function Anthropic.new(api_key, model, opts)
    opts = opts or {}
    local config = {
        api_key = api_key,
        model = model,
        base_url = opts.base_url or "https://api.anthropic.com/v1",
        timeout = opts.timeout or 60000,  -- Anthropic can be slower
    }
    local self = BaseLLM.new(config)
    setmetatable(self, Anthropic)
    self._http = HttpClient.new(config.timeout)
    return self
end

function Anthropic:Complete(ctx, prompt, opts)
    opts = opts or {}
    local body = {
        model = self._model,
        max_tokens = opts.max_tokens or 4096,
        messages = {{role = "user", content = prompt}},
    }

    local headers = {
        ["x-api-key"] = self._api_key,
        ["anthropic-version"] = "2023-06-01",
        ["Content-Type"] = "application/json",
    }

    local response = self._http:Post(
        self._base_url .. "/messages",
        headers,
        body
    )

    return self:_parseResponse(response)
end

function Anthropic:_parseResponse(response)
    if response.error then
        error(string.format("API Error: %s", response.error.message))
    end

    return {
        content = response.content[1].text,
        usage = response.usage,
        model = response.model,
        stop_reason = response.stop_reason,
    }
end

return Anthropic
```

**Anthropic-Specific:**
- Uses `x-api-key` header (not `Authorization`)
- Requires `anthropic-version` header
- Returns content as array of blocks
- Higher default max_tokens (4096 vs 1024)
- Longer default timeout (60s vs 30s)

---

## Component 7: Gemini Provider

### Implementation

```lua
-- dslua/llms/providers/gemini.lua
local BaseLLM = require("dslua.llms.base")
local HttpClient = require("dslua.llms.http")

local Gemini = {}
Gemini.__index = Gemini
setmetatable(Gemini, {__index = BaseLLM})

function Gemini.new(api_key, model, opts)
    opts = opts or {}
    local config = {
        api_key = api_key,
        model = model,
        base_url = opts.base_url or "https://generativelanguage.googleapis.com/v1beta",
        timeout = opts.timeout or 30000,
    }
    local self = BaseLLM.new(config)
    setmetatable(self, Gemini)
    self._http = HttpClient.new(config.timeout)
    return self
end

function Gemini:Complete(ctx, prompt, opts)
    opts = opts or {}
    local body = {
        contents = {{
            parts = {{text = prompt}}
        }},
        generationConfig = {
            temperature = opts.temperature or 0.7,
            maxOutputTokens = opts.max_tokens or 1024,
        }
    }

    -- API key in URL query parameter
    local url = string.format("%s/models/%s:generateContent?key=%s",
        self._base_url,
        self._model,
        self._api_key
    )

    local headers = {
        ["Content-Type"] = "application/json",
    }

    local response = self._http:Post(url, headers, body)

    return self:_parseResponse(response)
end

function Gemini:_parseResponse(response)
    if response.error then
        error(string.format("API Error: %s", response.error.message))
    end

    return {
        content = response.candidates[1].content.parts[1].text,
        usage = response.usageMetadata,
        model = self._model,
        finishReason = response.candidates[1].finishReason,
    }
end

return Gemini
```

**Gemini-Specific:**
- API key in URL query parameter (not header)
- Different request structure (contents/parts)
- Nested response structure (candidates[1].content.parts[1].text)
- Uses `maxOutputTokens` instead of `max_tokens`

---

## Dependencies

### Vendored Libraries

**deps/lua-http/** - HTTP client library
- `src/socket/http.lua` - HTTP request handling
- `src/socket/url.lua` - URL parsing
- `src/ltn12.lua` - Sink/source utilities

**deps/dkjson/** - JSON encoder/decoder
- `dkjson.lua` - Main library
- No external C dependencies (pure Lua)

### Installation Commands

```bash
# Clone lua-http into deps/
git clone https://github.com/diegonehab/luasocket.git deps/lua-http

# Download dkjson
curl -o deps/dkjson.lua https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua
```

---

## Testing Strategy

### Unit Tests (Mock HTTP)

```lua
-- specs/llms/openai_http_spec.lua
describe("OpenAI Provider with HTTP", function()
    it("should call real OpenAI API when API key present", function()
        -- Only runs if OPENAI_API_KEY env var set
        local api_key = os.getenv("OPENAI_API_KEY")
        if not api_key then
            pending("OPENAI_API_KEY not set")
        end

        local openai = dslua.llms.OpenAI(api_key, "gpt-3.5-turbo")
        local ctx = dslua.Context.new()

        local result = openai:Complete(ctx, "Say 'test'")

        assert.is_not_nil(result.content)
        assert.is_not_nil(result.usage)
    end)
end)
```

### Integration Tests (Opt-In)

```bash
# Run with real API keys
OPENAI_API_KEY=sk-... busted specs/ -v
ANTHROPIC_API_KEY=sk-... busted specs/ -v
```

### Module Tests with Real Providers

```lua
-- specs/modules/chain_of_thought_integration_spec.lua
it("should work with real OpenAI provider", function()
    if not os.getenv("OPENAI_API_KEY") then pending() end

    local cot = dslua.ChainOfThought.new(signature)
    local openai = dslua.llms.OpenAI(os.getenv("OPENAI_API_KEY"), "gpt-3.5-turbo")
    local ctx = dslua.Context.new({llm = openai})

    local result = cot:Process(ctx, {question = "What is 2+2?"})

    assert.is_not_nil(result.answer)
    assert.is_not_nil(result.reasoning)
end)
```

---

## File Structure

```
dslua/
├── deps/
│   ├── lua-http/          # HTTP client
│   └── dkjson.lua         # JSON library
├── dslua/
│   ├── llms/
│   │   ├── http.lua                # NEW: HTTP client wrapper
│   │   ├── errors.lua              # NEW: Error types
│   │   ├── providers/
│   │   │   ├── openai.lua          # MODIFIED: Add HTTP
│   │   │   ├── anthropic.lua        # NEW: Anthropic provider
│   │   │   └── gemini.lua          # NEW: Gemini provider
│   │   └── init.lua                # MODIFIED: Export new providers
│   ├── modules/
│   │   ├── chain_of_thought.lua    # NEW: CoT module
│   │   ├── react.lua               # NEW: ReAct module
│   │   ├── refine.lua              # NEW: Refine module
│   │   └── init.lua                # MODIFIED: Export new modules
│   └── tools/
│       ├── base.lua                # NEW: Tool base class
│       └── init.lua                # NEW: Tool package
└── specs/
    ├── llms/
    │   ├── openai_http_spec.lua     # NEW: OpenAI HTTP tests
    │   ├── anthropic_spec.lua       # NEW: Anthropic tests
    │   └── gemini_spec.lua          # NEW: Gemini tests
    ├── modules/
    │   ├── chain_of_thought_spec.lua     # NEW: CoT tests
    │   ├── react_spec.lua                # NEW: ReAct tests
    │   └── refine_spec.lua               # NEW: Refine tests
    └── tools/
        └── base_spec.lua                # NEW: Tool tests
```

---

## Success Criteria

Phase 2 is complete when:

1. ✅ **HTTP Integration:**
   - OpenAI provider makes real API calls
   - Responses parsed correctly
   - Error handling works

2. ✅ **Modules Working:**
   - ChainOfThought produces reasoning + answer
   - ReAct executes tools and returns results
   - Refine improves answers through iteration

3. ✅ **Additional Providers:**
   - Anthropic provider functional
   - Gemini provider functional
   - Provider switching works

4. ✅ **Testing:**
   - All tests pass (mock + integration)
   - Code coverage >80%
   - Real API tests opt-in

5. ✅ **Documentation:**
   - README updated with Phase 2 features
   - Usage examples for all modules
   - Provider configuration docs

---

## Implementation Tasks (Detailed)

### Task 1: Vendor Dependencies
- Download lua-http to `deps/lua-http/`
- Download dkjson to `deps/dkjson.lua`
- Verify no conflicts with existing code
- Test loading both libraries

### Task 2: Implement HTTP Client
- Create `dslua/llms/http.lua`
- Implement Post() method
- Add timeout handling
- Write tests with mock HTTP

### Task 3: Update OpenAI Provider
- Modify `dslua/llms/providers/openai.lua`
- Implement real Complete() method
- Add response parsing
- Handle API errors
- Write tests

### Task 4: Implement ChainOfThought
- Create `dslua/modules/chain_of_thought.lua`
- Build CoT prompt template
- Parse reasoning and answer
- Write tests

### Task 5: Implement ReAct Module
- Create `dslua/modules/react.lua`
- Build iterative loop
- Add tool execution
- Parse ReAct steps
- Write tests

### Task 6: Create Tool System
- Create `dslua/tools/base.lua`
- Define Tool interface
- Create example tools (search, calculator)
- Write tests

### Task 7: Implement Refine Module
- Create `dslua/modules/refine.lua`
- Build refinement loop
- Create critique prompt
- Write tests

### Task 8: Implement Anthropic Provider
- Create `dslua/llms/providers/anthropic.lua`
- Handle Anthropic-specific headers
- Parse response format
- Write tests

### Task 9: Implement Gemini Provider
- Create `dslua/llms/providers/gemini.lua`
- Handle URL-based auth
- Parse nested response
- Write tests

### Task 10: Integration and Documentation
- Update main package exports
- Update README with Phase 2 features
- Add usage examples
- Run full test suite
- Update DESIGN.md

---

## Estimated Effort

- **HTTP Integration:** 2-3 hours
- **ChainOfThought:** 1-2 hours
- **ReAct:** 3-4 hours
- **Tools:** 1-2 hours
- **Refine:** 1-2 hours
- **Anthropic Provider:** 2-3 hours
- **Gemini Provider:** 2-3 hours
- **Testing:** 4-6 hours
- **Documentation:** 2-3 hours

**Total:** 18-30 hours (2-4 days of focused work)

---

## Next Steps After Phase 2

Once Phase 2 is complete, dslua will have:
- ✅ Functional LLM providers (3 providers)
- ✅ Advanced reasoning modules (CoT, ReAct, Refine)
- ✅ Tool execution framework
- ✅ Real-world usability

**Phase 3** will then add:
- Agent frameworks (ReAct agent, ACE)
- Tool chaining and composition
- Structured output (JSON adapters)
- More advanced tool registry

**Phase 4** will focus on:
- Optimizers (BootstrapFewShot, MIPRO, GEPA, SIMBA)
- Performance benchmarking
- Comprehensive documentation
- Example applications
