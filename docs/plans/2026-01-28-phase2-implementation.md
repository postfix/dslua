# Phase 2: HTTP Integration and Advanced Modules - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement HTTP-based LLM providers (OpenAI, Anthropic, Gemini) and advanced reasoning modules (ChainOfThought, ReAct, Refine) with tool execution capabilities.

**Architecture:** Metatable-based OOP with shared HTTP client wrapper. Providers use vendored lua-http for API calls and dkjson for JSON parsing. Modules compose prompts from signature fields and parse structured responses.

**Tech Stack:** LuaJIT 2.1+, lua-http (HTTP client), dkjson (JSON), busted (testing)

---

## Task 1: Vendor Dependencies

**Files:**
- Create: `deps/lua-http/` (cloned repository)
- Create: `deps/dkjson.lua` (downloaded file)
- Test: N/A (manual verification)

**Step 1: Download lua-http**

Run:
```bash
git clone https://github.com/diegonehab/luasocket.git deps/lua-http
```

Expected: Repository cloned to `deps/lua-http/`

**Step 2: Download dkjson**

Run:
```bash
curl -o deps/dkjson.lua https://raw.githubusercontent.com/LuaDist/dkjson/master/dkjson.lua
```

Expected: File downloaded to `deps/dkjson.lua`

**Step 3: Verify dependencies load**

Create and run `test_deps.lua`:
```lua
package.path = package.path .. ';./deps/?.lua;./deps/?/init.lua'

local http = require("socket.http")
local dkjson = require("dkjson")

print("✓ lua-http loaded")
print("✓ dkjson loaded")

-- Test dkjson
local data = {test = "value"}
local json = dkjson.encode(data)
print("✓ dkjson.encode:", json)

local decoded = dkjson.decode(json)
print("✓ dkjson.decode:", decoded.test)
```

Run: `luajit test_deps.lua`
Expected: All checks pass

**Step 4: Clean up**

Run:
```bash
rm test_deps.lua
```

**Step 5: Commit**

```bash
git add deps/
git commit -m "chore: vendor lua-http and dkjson dependencies

Add lua-http for HTTP client functionality and dkjson for JSON encoding/decoding.
Zero-install setup - no external package manager required.

Dependencies:
- lua-http: https://github.com/diegonehab/luasocket
- dkjson: https://github.com/LuaDist/dkjson"
```

---

## Task 2: Create HTTP Client Wrapper

**Files:**
- Create: `dslua/llms/http.lua`
- Create: `specs/llms/http_spec.lua`

**Step 1: Write the failing test**

Create `specs/llms/http_spec.lua`:

```lua
describe("HttpClient", function()
    it("should create client with default timeout", function()
        local HttpClient = require("dslua.llms.http")
        local client = HttpClient.new()

        assert.is.equal(30000, client._timeout)
    end)

    it("should create client with custom timeout", function()
        local HttpClient = require("dslua.llms.http")
        local client = HttpClient.new(60000)

        assert.is.equal(60000, client._timeout)
    end)

    it("should encode JSON body", function()
        local HttpClient = require("dslua.llms.http")
        local dkjson = require("dkjson")

        -- Test JSON encoding separately
        local body = {test = "value", number = 42}
        local json = dkjson.encode(body)

        assert.is_not_nil(string.find(json, '"test"'))
        assert.is_not_nil(string.find(json, '"value"'))
    end)

    it("should decode JSON response", function()
        local HttpClient = require("dslua.llms.http")
        local dkjson = require("dkjson")

        local json = '{"result": "success", "count": 5}'
        local decoded = dkjson.decode(json)

        assert.is.equal("success", decoded.result)
        assert.is.equal(5, decoded.count)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/llms/http_spec.lua -v`
Expected: FAIL with "module 'dslua.llms.http' not found"

**Step 3: Write minimal implementation**

Create `dslua/llms/http.lua`:

```lua
local http = require("socket.http")
local ltn12 = require("ltn12")
local dkjson = require("dkjson")

local HttpClient = {}
HttpClient.__index = HttpClient

function HttpClient.new(timeout)
    return setmetatable({
        _timeout = timeout or 30000,
    }, HttpClient)
end

function HttpClient:Timeout()
    return self._timeout
end

function HttpClient:Post(url, headers, body)
    local request_body = dkjson.encode(body)
    local response_body = {}

    -- Parse URL to get host and path
    local parsed_url = self:_parseURL(url)

    local response, status, response_headers = http.request({
        url = url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_body),
    })

    if not response then
        error(string.format("HTTP request failed: %s", status))
    end

    if status >= 400 then
        error(string.format("HTTP Error %d: %s", status, table.concat(response_body)))
    end

    return dkjson.decode(table.concat(response_body))
end

function HttpClient:_parseURL(url)
    -- Simple URL parser - lua-http handles most of this
    return url
end

return HttpClient
```

**Step 4: Run test to verify it passes**

Run: `busted specs/llms/http_spec.lua -v`
Expected: PASS (4 tests passing)

**Step 5: Commit**

```bash
git add dslua/llms/http.lua specs/llms/
git commit -m "feat(llms): implement HTTP client wrapper

Add HttpClient for unified HTTP requests across all LLM providers.
Features:
- Configurable timeout (default 30s)
- Automatic JSON encoding/decoding via dkjson
- HTTP error detection and reporting
- Uses lua-http for transport layer

Tests: 4 passing (client creation, JSON encoding/decoding)"
```

---

## Task 3: Create Error Types

**Files:**
- Create: `dslua/llms/errors.lua`
- Create: `specs/llms/errors_spec.lua`

**Step 1: Write the failing test**

Create `specs/llms/errors_spec.lua`:

```lua
describe("LLM Errors", function()
    local Errors = require("dslua.llms.errors")

    it("should create HTTPError", function()
        local err = Errors.HTTPError(404, "Not found")

        assert.is.equal("HTTPError", err.type)
        assert.is.equal(404, err.status)
        assert.is.equal("Not found", err.message)
    end)

    it("should create APIError", function()
        local err = Errors.APIError("invalid_request", "Missing required field")

        assert.is.equal("APIError", err.type)
        assert.is.equal("invalid_request", err.code)
        assert.is.equal("Missing required field", err.message)
    end)

    it("should create RateLimitError", function()
        local err = Errors.RateLimitError(60)

        assert.is.equal("RateLimitError", err.type)
        assert.is.equal(60, err.retry_after)
    end)

    it("should format error as string", function()
        local err = Errors.HTTPError(500, "Server error")
        local str = tostring(err)

        assert.is_not_nil(string.find(str, "HTTPError"))
        assert.is_not_nil(string.find(str, "500"))
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/llms/errors_spec.lua -v`
Expected: FAIL with "module 'dslua.llms.errors' not found"

**Step 3: Write minimal implementation**

Create `dslua/llms/errors.lua`:

```lua
local Errors = {}

function Errors.HTTPError(status, message)
    local err = {
        type = "HTTPError",
        status = status,
        message = message,
    }
    setmetatable(err, {
        __tostring = function(self)
            return string.format("[%s] %d: %s", self.type, self.status, self.message)
        end
    })
    return err
end

function Errors.APIError(code, message)
    local err = {
        type = "APIError",
        code = code,
        message = message,
    }
    setmetatable(err, {
        __tostring = function(self)
            return string.format("[%s] %s: %s", self.type, self.code, self.message)
        end
    })
    return err
end

function Errors.RateLimitError(retry_after)
    local err = {
        type = "RateLimitError",
        retry_after = retry_after,
    }
    setmetatable(err, {
        __tostring = function(self)
            return string.format("[%s] Retry after %d seconds", self.type, self.retry_after)
        end
    })
    return err
end

return Errors
```

**Step 4: Run test to verify it passes**

Run: `busted specs/llms/errors_spec.lua -v`
Expected: PASS (4 tests passing)

**Step 5: Commit**

```bash
git add dslua/llms/errors.lua specs/llms/
git commit -m "feat(llms): implement error type classification

Add structured error types for HTTP, API, and rate limit errors.
Each error type has relevant metadata and string formatting.

Tests: 4 passing (HTTPError, APIError, RateLimitError, tostring)"
```

---

## Task 4: Update OpenAI Provider with HTTP

**Files:**
- Modify: `dslua/llms/providers/openai.lua`
- Modify: `specs/llms/openai_spec.lua`

**Step 1: Write the failing test**

Add to `specs/llms/openai_spec.lua`:

```lua
describe("OpenAI Provider with HTTP", function()
    local llms = require("dslua.llms")

    it("should make real API call when API key provided", function()
        -- Only run if OPENAI_API_KEY is set
        local api_key = os.getenv("OPENAI_API_KEY")
        if not api_key then
            pending("OPENAI_API_KEY environment variable not set")
            return
        end

        local llm = llms.OpenAI(api_key, "gpt-3.5-turbo")
        local ctx = require("dslua.core.context").new()

        local result = llm:Complete(ctx, "Say 'test'")

        assert.is_not_nil(result.content)
        assert.is_not_nil(result.usage)
        assert.is_not_nil(result.model)
    end)

    it("should handle API errors gracefully", function()
        local llm = llms.OpenAI("invalid-key", "gpt-3.5-turbo")
        local ctx = require("dslua.core.context").new()

        assert.has_error(function()
            llm:Complete(ctx, "test")
        end)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/llms/openai_spec.lua -v`
Expected: FAIL (HTTP integration not yet implemented)

**Step 3: Write implementation**

Modify `dslua/llms/providers/openai.lua`:

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

function OpenAI:_buildRequestBody(prompt, opts)
    opts = opts or {}
    return {
        model = self._model,
        messages = {{role = "user", content = prompt}},
        temperature = opts.temperature or 0.7,
        max_tokens = opts.max_tokens or 1024,
    }
end

return OpenAI
```

**Step 4: Run test to verify it passes**

Run: `busted specs/llms/openai_spec.lua -v`
Expected: PASS (or skip if no API key)

**Step 5: Commit**

```bash
git add dslua/llms/providers/openai.lua specs/llms/openai_spec.lua
git commit -m "feat(llms): implement real HTTP calls for OpenAI provider

OpenAI provider now makes actual API calls using lua-http.
Features:
- Real API integration with OpenAI
- Response parsing (content, usage, model, finish_reason)
- Error handling for API errors
- Optional integration tests (require OPENAI_API_KEY)

Tests: Integration tests opt-in via environment variable"
```

---

## Task 5: Implement ChainOfThought Module

**Files:**
- Create: `dslua/modules/chain_of_thought.lua`
- Modify: `dslua/modules/init.lua`
- Create: `specs/modules/chain_of_thought_spec.lua`

**Step 1: Write the failing test**

Create `specs/modules/chain_of_thought_spec.lua`:

```lua
describe("ChainOfThought", function()
    local Field = require("dslua.core.field")
    local Signature = require("dslua.core.signature")
    local Context = require("dslua.core.context")

    it("should create ChainOfThought with signature", function()
        local ChainOfThought = require("dslua.modules.chain_of_thought")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local cot = ChainOfThought.new(signature)

        assert.is.equal(signature, cot:Signature())
    end)

    it("should build CoT prompt with instruction", function()
        local ChainOfThought = require("dslua.modules.chain_of_thought")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local cot = ChainOfThought.new(signature)

        local prompt = cot:_buildCOTPrompt({question = "What is 2+2?"})

        assert.is_not_nil(string.find(prompt, "Think step-by-step"))
        assert.is_not_nil(string.find(prompt, "What is 2+2?"))
        assert.is_not_nil(string.find(prompt, "Reasoning:"))
        assert.is_not_nil(string.find(prompt, "Answer:"))
    end)

    it("should parse reasoning and answer from response", function()
        local ChainOfThought = require("dslua.modules.chain_of_thought")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local cot = ChainOfThought.new(signature)

        local response = {
            content = "Reasoning: Let's think step by step.\n\nAnswer: 4"
        }
        local result = cot:_parseOutput(response)

        assert.is.equal("4", result.answer)
        assert.is_not_nil(string.find(result.reasoning, "step by step"))
    end)

    it("should process with LLM and return structured result", function()
        local ChainOfThought = require("dslua.modules.chain_of_thought")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local cot = ChainOfThought.new(signature)

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Reasoning: 2+2=4\nAnswer: 4"}
            end
        }
        local ctx = Context.new({llm = mock_llm})

        local result = cot:Process(ctx, {question = "What is 2+2?"})

        assert.is.equal("4", result.answer)
        assert.is_not_nil(result.reasoning)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/modules/chain_of_thought_spec.lua -v`
Expected: FAIL with "module 'dslua.modules.chain_of_thought' not found"

**Step 3: Write minimal implementation**

Create `dslua/modules/chain_of_thought.lua`:

```lua
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
    local reasoning = content:match("Reasoning:%s*(.-)%s*Answer:") or ""
    local answer = content:match("Answer:%s*(.+)") or content

    return {
        reasoning = reasoning,
        answer = answer,
        raw = content,
    }
end

return ChainOfThought
```

Update `dslua/modules/init.lua`:

```lua
local M = {}

M.Base = require("dslua.modules.base")
M.Predict = require("dslua.modules.predict")
M.ChainOfThought = require("dslua.modules.chain_of_thought")

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/modules/chain_of_thought_spec.lua -v`
Expected: PASS (4 tests passing)

**Step 5: Commit**

```bash
git add dslua/modules/chain_of_thought.lua dslua/modules/init.lua specs/modules/
git commit -m "feat(modules): implement ChainOfThought module

ChainOfThought prompts LLM to show reasoning before answering.
Features:
- Step-by-step reasoning instruction
- Structured output parsing (reasoning + answer)
- Falls back to full response if parsing fails
- Extends Predict module

Tests: 4 passing (creation, prompt building, parsing, end-to-end)"
```

---

## Task 6: Implement Tool Base Class

**Files:**
- Create: `dslua/tools/base.lua`
- Create: `dslua/tools/init.lua`
- Create: `specs/tools/base_spec.lua`

**Step 1: Write the failing test**

Create `specs/tools/base_spec.lua`:

```lua
describe("Tool", function()
    it("should create tool with name and function", function()
        local Tool = require("dslua.tools.base")
        local tool = Tool.new("test", {
            description = "A test tool",
            func = function(args)
                return {result = "success"}
            end
        })

        assert.is.equal("test", tool:Name())
        assert.is.equal("A test tool", tool:Description())
    end)

    it("should execute tool function", function()
        local Tool = require("dslua.tools.base")
        local tool = Tool.new("calculator", {
            description = "Calculate expression",
            func = function(args)
                return {result = args.a + args.b}
            end
        })

        local result = tool:Execute({a = 2, b = 3})

        assert.is.equal(5, result.result)
    end)

    it("should pass args to function", function()
        local Tool = require("dslua.tools.base")
        local received_args = nil

        local tool = Tool.new("args_test", {
            description = "Test args passing",
            func = function(args)
                received_args = args
                return {}
            end
        })

        tool:Execute({test = "value", number = 42})

        assert.is.equal("value", received_args.test)
        assert.is.equal(42, received_args.number)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/tools/base_spec.lua -v`
Expected: FAIL with "module 'dslua.tools.base' not found"

**Step 3: Write minimal implementation**

Create `dslua/tools/base.lua`:

```lua
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

Create `dslua/tools/init.lua`:

```lua
local M = {}

M.Base = require("dslua.tools.base")

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/tools/base_spec.lua -v`
Expected: PASS (3 tests passing)

**Step 5: Commit**

```bash
git add dslua/tools/ specs/tools/
git commit -m "feat(tools): implement Tool base class

Add Tool abstraction for extensible tool execution.
Features:
- Named tools with descriptions
- Function-based execution
- Argument passing

Tests: 3 passing (creation, execution, args passing)"
```

---

## Task 7: Implement ReAct Module

**Files:**
- Create: `dslua/modules/react.lua`
- Modify: `dslua/modules/init.lua`
- Create: `specs/modules/react_spec.lua`

**Step 1: Write the failing test**

Create `specs/modules/react_spec.lua`:

```lua
describe("ReAct", function()
    local Field = require("dslua.core.field")
    local Signature = require("dslua.core.signature")
    local Context = require("dslua.core.context")
    local Tool = require("dslua.tools.base")

    it("should create ReAct with signature and tools", function()
        local ReAct = require("dslua.modules.react")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local tools = {
            Tool.new("search", {
                description = "Search the web",
                func = function(args) return {result = "found"} end
            })
        }
        local react = ReAct.new(signature, {tools = tools})

        assert.is.equal(signature, react:Signature())
        assert.is.equal(1, #react._tools)
    end)

    it("should build ReAct prompt with history", function()
        local ReAct = require("dslua.modules.react")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local react = ReAct.new(signature, {tools = {}})

        local state = {
            input = {question = "What is the capital of France?"},
            observations = {"Paris is the capital."},
            thoughts = {},
        }

        local prompt = react:_buildReActPrompt(state, 2)

        assert.is_not_nil(string.find(prompt, "What is the capital"))
        assert.is_not_nil(string.find(prompt, "Paris"))
        assert.is_not_nil(string.find(prompt, "Thought 2:"))
    end)

    it("should parse ReAct step with action", function()
        local ReAct = require("dslua.modules.react")
        local signature = Signature.new({}, {})
        local react = ReAct.new(signature, {tools = {}})

        local content = "Thought: I need to search.\nAction: search[Paris]"
        local step = react:_parseStep(content)

        assert.is.equal("I need to search.", step.thought)
        assert.is.equal("search", step.action)
    end)

    it("should execute single turn and finish", function()
        local ReAct = require("dslua.modules.react")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Thought: The answer is 42\nAction: finish[42]"}
            end
        }

        local react = ReAct.new(signature, {tools = {}})
        local ctx = Context.new({llm = mock_llm})

        local result = react:Process(ctx, {question = "What is 6*7?"})

        assert.is.equal("42", result.answer)
        assert.is.equal(1, result.iterations)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/modules/react_spec.lua -v`
Expected: FAIL with "module 'dslua.modules.react' not found"

**Step 3: Write minimal implementation**

Create `dslua/modules/react.lua`:

```lua
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
    local llm = ctx:LLM() or self:LLM()
    local state = {
        thoughts = {},
        actions = {},
        observations = {},
        input = input,
    }

    for i = 1, self._maxIterations do
        -- Generate thought and action
        local prompt = self:_buildReActPrompt(state, i)
        local response = llm:Complete(ctx, prompt)
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
        table.insert(parts, string.format("Observation %d: %s", i, tostring(obs)))
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
    -- Parse: Thought: ... Action: tool_name[args] or finish[answer]
    local thought = content:match("Thought:%s*(.-)\n") or ""

    local action_match = content:match("Action:%s*(.-)\n")
    if not action_match then
        action_match = content:match("Action:%s*(.+)$") or ""
    end

    local action, args = action_match:match("^(.+)%[(.+)%]$")

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
        args = args,
    }
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

Update `dslua/modules/init.lua`:

```lua
local M = {}

M.Base = require("dslua.modules.base")
M.Predict = require("dslua.modules.predict")
M.ChainOfThought = require("dslua.modules.chain_of_thought")
M.ReAct = require("dslua.modules.react")

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/modules/react_spec.lua -v`
Expected: PASS (4 tests passing)

**Step 5: Commit**

```bash
git add dslua/modules/react.lua dslua/modules/init.lua specs/modules/
git commit -m "feat(modules): implement ReAct module with tool use

ReAct prompts LLM to reason and act iteratively with tools.
Features:
- Thought-action-observation loop
- Tool execution with arguments
- Finish action to terminate
- History tracking across iterations

Tests: 4 passing (creation, prompt building, parsing, end-to-end)"
```

---

## Task 8: Implement Refine Module

**Files:**
- Create: `dslua/modules/refine.lua`
- Modify: `dslua/modules/init.lua`
- Create: `specs/modules/refine_spec.lua`

**Step 1: Write the failing test**

Create `specs/modules/refine_spec.lua`:

```lua
describe("Refine", function()
    local Field = require("dslua.core.field")
    local Signature = require("dslua.core.signature")
    local Context = require("dslua.core.context")

    it("should create Refine with signature", function()
        local Refine = require("dslua.modules.refine")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local refine = Refine.new(signature, {max_iterations = 2})

        assert.is.equal(signature, refine:Signature())
        assert.is.equal(2, refine._maxIterations)
    end)

    it("should build initial prompt on first iteration", function()
        local Refine = require("dslua.modules.refine")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local refine = Refine.new(signature)

        local prompt = refine:_buildRefinePrompt(
            {question = "What is 2+2?"},
            {content = ""},
            1
        )

        assert.is_not_nil(string.find(prompt, "What is 2+2?"))
        assert.is_not_nil(string.find(prompt, "Answer:"))
    end)

    it("should build refinement prompt on subsequent iterations", function()
        local Refine = require("dslua.modules.refine")
        local signature = Signature.new({}, {})
        local refine = Refine.new(signature)

        local prompt = refine:_buildRefinePrompt(
            {question = "Test"},
            {content = "Previous answer"},
            2
        )

        assert.is_not_nil(string.find(prompt, "Previous answer"))
        assert.is_not_nil(string.find(prompt, "critique"))
    end)

    it("should refine answer over multiple iterations", function()
        local Refine = require("dslua.modules.refine")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local refine = Refine.new(signature, {max_iterations = 2})

        local call_count = 0
        local mock_llm = {
            Complete = function(self, ctx, prompt)
                call_count = call_count + 1
                if call_count == 1 then
                    return {content = "Initial answer about 2+2=4"}
                else
                    return {content = "Refined answer: 2+2 equals 4"}
                end
            end
        }

        local ctx = Context.new({llm = mock_llm})
        local result = refine:Process(ctx, {question = "What is 2+2?"})

        assert.is.equal(2, result.iterations)
        assert.is_not_nil(string.find(result.answer, "equals 4"))
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/modules/refine_spec.lua -v`
Expected: FAIL with "module 'dslua.modules.refine' not found"

**Step 3: Write minimal implementation**

Create `dslua/modules/refine.lua`:

```lua
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

Update `dslua/modules/init.lua`:

```lua
local M = {}

M.Base = require("dslua.modules.base")
M.Predict = require("dslua.modules.predict")
M.ChainOfThought = require("dslua.modules.chain_of_thought")
M.ReAct = require("dslua.modules.react")
M.Refine = require("dslua.modules.refine")

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/modules/refine_spec.lua -v`
Expected: PASS (4 tests passing)

**Step 5: Commit**

```bash
git add dslua/modules/refine.lua dslua/modules/init.lua specs/modules/
git commit -m "feat(modules): implement Refine module

Refine iteratively improves answers through self-critique.
Features:
- Multiple refinement iterations (default 3)
- Critique prompts for accuracy, completeness, clarity
- Extracts refined answer from response

Tests: 4 passing (creation, initial prompt, refinement prompt, iterations)"
```

---

## Task 9: Implement Anthropic Provider

**Files:**
- Create: `dslua/llms/providers/anthropic.lua`
- Modify: `dslua/llms/init.lua`
- Create: `specs/llms/anthropic_spec.lua`

**Step 1: Write the failing test**

Create `specs/llms/anthropic_spec.lua`:

```lua
describe("Anthropic Provider", function()
    local llms = require("dslua.llms")

    it("should create Anthropic provider", function()
        local llm = llms.Anthropic("test-key", "claude-3-sonnet")

        assert.is.equal("test-key", llm:APIKey())
        assert.is.equal("claude-3-sonnet", llm:Model())
        assert.is.equal("https://api.anthropic.com/v1", llm:BaseURL())
    end)

    it("should build Anthropic request body", function()
        local llm = llms.Anthropic("test-key", "claude-3-sonnet")

        local body = llm:_buildRequestBody("Hello", {max_tokens = 100})

        assert.is.equal("claude-3-sonnet", body.model)
        assert.is.equal(100, body.max_tokens)
        assert.is.equal(1, #body.messages)
        assert.is.equal("user", body.messages[1].role)
    end)

    it("should make real API call when API key provided", function()
        local api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key then
            pending("ANTHROPIC_API_KEY environment variable not set")
            return
        end

        local llm = llms.Anthropic(api_key, "claude-3-haiku-20240307")
        local ctx = require("dslua.core.context").new()

        local result = llm:Complete(ctx, "Say 'test'")

        assert.is_not_nil(result.content)
        assert.is_not_nil(result.usage)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/llms/anthropic_spec.lua -v`
Expected: FAIL with "module 'dslua.llms.providers.anthropic' not found"

**Step 3: Write minimal implementation**

Create `dslua/llms/providers/anthropic.lua`:

```lua
local BaseLLM = require("dslua.llms.base")
local HttpClient = require("dslua.llms.http")
local Errors = require("dslua.llms.errors")

local Anthropic = {}
Anthropic.__index = Anthropic
setmetatable(Anthropic, {__index = BaseLLM})

function Anthropic.new(api_key, model, opts)
    opts = opts or {}
    local config = {
        api_key = api_key,
        model = model,
        base_url = opts.base_url or "https://api.anthropic.com/v1",
        timeout = opts.timeout or 60000,
    }
    local self = BaseLLM.new(config)
    setmetatable(self, Anthropic)
    self._http = HttpClient.new(config.timeout)
    return self
end

function Anthropic:Complete(ctx, prompt, opts)
    opts = opts or {}
    local body = self:_buildRequestBody(prompt, opts)
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

function Anthropic:_buildRequestBody(prompt, opts)
    return {
        model = self._model,
        max_tokens = opts.max_tokens or 4096,
        messages = {{role = "user", content = prompt}},
    }
end

function Anthropic:_parseResponse(response)
    if response.error then
        error(Errors.APIError(response.error.type, response.error.message))
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

Update `dslua/llms/init.lua`:

```lua
local M = {}

function M.OpenAI(api_key, model, opts)
    return require("dslua.llms.providers.openai").new(api_key, model, opts)
end

function M.Anthropic(api_key, model, opts)
    return require("dslua.llms.providers.anthropic").new(api_key, model, opts)
end

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/llms/anthropic_spec.lua -v`
Expected: PASS (or skip if no API key)

**Step 5: Commit**

```bash
git add dslua/llms/providers/anthropic.lua dslua/llms/init.lua specs/llms/
git commit -m "feat(llms): implement Anthropic provider

Add Anthropic Claude API support with x-api-key header.
Features:
- Anthropic-specific authentication (x-api-key header)
- API version header (anthropic-version)
- Response parsing (content array, stop_reason)
- Longer default timeout (60s) for Claude
- Integration tests (require ANTHROPIC_API_KEY)

Tests: 3 passing (creation, request building, integration opt-in)"
```

---

## Task 10: Implement Gemini Provider

**Files:**
- Create: `dslua/llms/providers/gemini.lua`
- Modify: `dslua/llms/init.lua`
- Create: `specs/llms/gemini_spec.lua`

**Step 1: Write the failing test**

Create `specs/llms/gemini_spec.lua`:

```lua
describe("Gemini Provider", function()
    local llms = require("dslua.llms")

    it("should create Gemini provider", function()
        local llm = llms.Gemini("test-key", "gemini-pro")

        assert.is.equal("test-key", llm:APIKey())
        assert.is.equal("gemini-pro", llm:Model())
    end)

    it("should build Gemini request body", function()
        local llm = llms.Gemini("test-key", "gemini-pro")

        local body = llm:_buildRequestBody("Hello", {})

        assert.is_not_nil(body.contents)
        assert.is.equal(1, #body.contents)
        assert.is_not_nil(body.contents[1].parts)
    end)

    it("should make real API call when API key provided", function()
        local api_key = os.getenv("GEMINI_API_KEY")
        if not api_key then
            pending("GEMINI_API_KEY environment variable not set")
            return
        end

        local llm = llms.Gemini(api_key, "gemini-pro")
        local ctx = require("dslua.core.context").new()

        local result = llm:Complete(ctx, "Say 'test'")

        assert.is_not_nil(result.content)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/llms/gemini_spec.lua -v`
Expected: FAIL with "module 'dslua.llms.providers.gemini' not found"

**Step 3: Write minimal implementation**

Create `dslua/llms/providers/gemini.lua`:

```lua
local BaseLLM = require("dslua.llms.base")
local HttpClient = require("dslua.llms.http")
local Errors = require("dslua.llms.errors")

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
    local body = self:_buildRequestBody(prompt, opts)

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

function Gemini:_buildRequestBody(prompt, opts)
    return {
        contents = {{
            parts = {{text = prompt}}
        }},
        generationConfig = {
            temperature = opts.temperature or 0.7,
            maxOutputTokens = opts.max_tokens or 1024,
        }
    }
end

function Gemini:_parseResponse(response)
    if response.error then
        error(Errors.APIError(response.error.code, response.error.message))
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

Update `dslua/llms/init.lua`:

```lua
local M = {}

function M.OpenAI(api_key, model, opts)
    return require("dslua.llms.providers.openai").new(api_key, model, opts)
end

function M.Anthropic(api_key, model, opts)
    return require("dslua.llms.providers.anthropic").new(api_key, model, opts)
end

function M.Gemini(api_key, model, opts)
    return require("dslua.llms.providers.gemini").new(api_key, model, opts)
end

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/llms/gemini_spec.lua -v`
Expected: PASS (or skip if no API key)

**Step 5: Commit**

```bash
git add dslua/llms/providers/gemini.lua dslua/llms/init.lua specs/llms/
git commit -m "feat(llms): implement Gemini provider

Add Google Gemini API support with URL-based authentication.
Features:
- API key in URL query parameter
- Nested request structure (contents/parts)
- Different response format (candidates[1].content.parts[1].text)
- Integration tests (require GEMINI_API_KEY)

Tests: 3 passing (creation, request building, integration opt-in)"
```

---

## Task 11: Update Main Package Exports

**Files:**
- Modify: `dslua/init.lua`
- Create: `specs/phase2_integration_spec.lua`

**Step 1: Write the failing test**

Create `specs/phase2_integration_spec.lua`:

```lua
describe("Phase 2 Integration", function()
    it("should expose all Phase 2 modules from main package", function()
        local dslua = require("dslua")

        assert.is.truthy(dslua.ChainOfThought)
        assert.is.truthy(dslua.ReAct)
        assert.is.truthy(dslua.Refine)
    end)

    it("should expose all providers from main package", function()
        local dslua = require("dslua")

        assert.is.truthy(dslua.llms.Anthropic)
        assert.is.truthy(dslua.llms.Gemini)
    end)

    it("should support complete ChainOfThought flow with real provider", function()
        local dslua = require("dslua")
        local api_key = os.getenv("OPENAI_API_KEY")

        if not api_key then
            pending("OPENAI_API_KEY not set")
            return
        end

        local signature = dslua.Signature.new(
            {dslua.Field.new("question")},
            {dslua.Field.new("answer")}
        )
        local cot = dslua.ChainOfThought.new(signature)
        local llm = dslua.llms.OpenAI(api_key, "gpt-3.5-turbo")
        local ctx = dslua.Context.new({llm = llm})

        local result = cot:Process(ctx, {question = "What is 2+2?"})

        assert.is_not_nil(result.answer)
        assert.is_not_nil(result.reasoning)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/phase2_integration_spec.lua -v`
Expected: FAIL (modules not exported)

**Step 3: Write minimal implementation**

Modify `dslua/init.lua`:

```lua
local M = {}

-- Core types
M.Field = require("dslua.core.field")
M.Signature = require("dslua.core.signature")
M.Context = require("dslua.core.context")

-- Modules
M.Predict = require("dslua.modules.predict")
M.ChainOfThought = require("dslua.modules.chain_of_thought")
M.ReAct = require("dslua.modules.react")
M.Refine = require("dslua.modules.refine")

-- Tools
M.Tool = require("dslua.tools.base")

-- LLM providers
M.llms = require("dslua.llms")

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/phase2_integration_spec.lua -v`
Expected: PASS (or skip if no API key)

**Step 5: Commit**

```bash
git add dslua/init.lua specs/
git commit -m "feat(package): export Phase 2 modules and tools

Expose all Phase 2 functionality through main package:
- ChainOfThought, ReAct, Refine modules
- Tool base class
- All LLM providers (OpenAI, Anthropic, Gemini)

Tests: 3 passing (API exposure, providers, end-to-end integration)"
```

---

## Task 12: Run Full Test Suite and Verify

**Files:**
- All test files
- Modify: `README.md`
- Modify: `DESIGN.md`

**Step 1: Run complete test suite**

Run: `busted specs/ -v`
Expected: All tests passing (50+ tests)

**Step 2: Check test count**

Run:
```bash
find specs/ -name "*_spec.lua" -exec echo "File: {}" \; -exec grep -c "^    it(" {} \; | awk '{sum+=$2} END {print "Total tests:", sum}'
```

Expected: 50+ tests

**Step 3: Verify package loading**

Create and run `verify_phase2.lua`:
```lua
package.path = package.path .. ';./dslua/?.lua;./?.lua;./deps/?.lua;./deps/?/init.lua'

local dslua = require("dslua")

print("✓ Package loaded")
print("✓ Core types:", dslua.Field and dslua.Signature and dslua.Context)
print("✓ Modules:", dslua.Predict and dslua.ChainOfThought and dslua.ReAct and dslua.Refine)
print("✓ Tools:", dslua.Tool)
print("✓ Providers:", dslua.llms.OpenAI and dslua.llms.Anthropic and dslua.llms.Gemini)

-- Test with mock
local cot = dslua.ChainOfThought.new(
    dslua.Signature.new(
        {dslua.Field.new("question")},
        {dslua.Field.new("answer")}
    )
)

local mock_llm = {
    Complete = function(self, ctx, prompt)
        return {content = "Reasoning: test\nAnswer: 42"}
    end
}

local ctx = dslua.Context.new({llm = mock_llm})
local result = cot:Process(ctx, {question = "test"})

print("✓ ChainOfThought works:", result.answer == "42")
print("\n✅ Phase 2 verification complete!")
```

Run: `luajit verify_phase2.lua`
Expected: All checks pass

**Step 4: Clean up**

Run:
```bash
rm verify_phase2.lua
```

**Step 5: Update README**

Modify `README.md` to reflect Phase 2 completion:

```markdown
## Current Status (Phase 2 Complete)

✅ **Implemented:**
- Core abstractions: Field, Signature, Context, Module base
- Predict module for direct LLM prediction
- ChainOfThought module with reasoning extraction
- ReAct module with tool use and iteration
- Refine module with self-critique
- Tool system for extensible execution
- OpenAI, Anthropic, Gemini providers with HTTP integration
- CLI skeleton

🚧 **In Progress:**
- HTTP client integration (Complete!)
- Advanced agent frameworks
- Optimizers (MIPRO, BootstrapFewShot, etc.)
```

**Step 6: Update DESIGN.md**

Add to Implementation Progress section:

```markdown
### Phase 2: HTTP Integration and Advanced Modules ✅ COMPLETE (2026-01-28)
- [x] Vendor dependencies (lua-http, dkjson)
- [x] HTTP client wrapper
- [x] Error classification system
- [x] OpenAI provider with real API calls
- [x] ChainOfThought module
- [x] ReAct module with tool use
- [x] Refine module with iteration
- [x] Tool base class
- [x] Anthropic provider
- [x] Gemini provider
- [x] Package exports updated

**Results:**
- 50+ tests passing (100% pass rate)
- 11 focused commits
- All providers functional with real APIs
- All advanced modules working
- Ready for Phase 3
```

**Step 7: Final Phase 2 commit**

```bash
git add README.md DESIGN.md
git commit -m "docs: mark Phase 2 as complete

Phase 2 achievements:
✅ HTTP client integration (lua-http + dkjson)
✅ Functional providers (OpenAI, Anthropic, Gemini)
✅ Advanced modules (ChainOfThought, ReAct, Refine)
✅ Tool system base class
✅ 50+ tests passing
✅ Real API integration working

dslua is now a fully functional LLM framework with multiple providers
and advanced reasoning capabilities. Ready for Phase 3 (Agents)."
```

---

## Summary

Phase 2 implements HTTP-based LLM providers and advanced reasoning modules in 12 focused tasks:

**Tasks:**
1. Vendor dependencies (lua-http, dkjson)
2. HTTP client wrapper
3. Error types
4. OpenAI provider with HTTP
5. ChainOfThought module
6. Tool base class
7. ReAct module
8. Refine module
9. Anthropic provider
10. Gemini provider
11. Package exports
12. Final verification

**Expected Outcomes:**
- 50+ tests passing
- 11 commits
- Real API calls working
- All modules functional
- Ready for Phase 3

**Estimated Time:** 18-30 hours (2-4 days)
