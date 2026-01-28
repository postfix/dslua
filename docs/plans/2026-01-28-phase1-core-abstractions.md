# Phase 1: Core Abstractions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement core DSPy abstractions (Signature, Field, Context, Module base, Predict) and OpenAI provider to establish the foundation for all dslua functionality.

**Architecture:** Metatable-based object-oriented system with hierarchical package structure. Each core type (Signature, Field, Context, Module) is implemented as a Lua table with metatable for method dispatch, supporting fluent method chaining. OpenAI provider uses vendored HTTP client for API calls.

**Tech Stack:** LuaJIT 2.1+, dkjson (JSON), lua-http (HTTP client), busted (testing)

---

## Task 1: Create Field Type (Core Data Structure)

**Files:**
- Create: `dslua/core/field.lua`
- Create: `specs/core/field_spec.lua`

**Step 1: Write the failing test**

Create `specs/core/field_spec.lua`:

```lua
describe("Field", function()
    it("should create field with name", function()
        local Field = require("dslua.core.field")
        local field = Field.new("question")

        assert.is.equal("question", field:Name())
        assert.is.equal("", field:Description())
    end)

    it("should create field with name and description", function()
        local Field = require("dslua.core.field")
        local field = Field.new("question", {desc = "The question to answer"})

        assert.is.equal("question", field:Name())
        assert.is.equal("The question to answer", field:Description())
    end)

    it("should support fluent description setting", function()
        local Field = require("dslua.core.field")
        local field = Field.new("question"):WithDescription("Test desc")

        assert.is.equal("Test desc", field:Description())
        assert.is.equal(field, field:WithDescription("Test"))  -- Returns self
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/core/field_spec.lua -v`
Expected: FAIL with "module 'dslua.core.field' not found"

**Step 3: Write minimal implementation**

Create `dslua/core/field.lua`:

```lua
local Field = {}
Field.__index = Field

function Field.new(name, opts)
    opts = opts or {}
    local self = {
        _name = name,
        _description = opts.desc or "",
    }
    return setmetatable(self, Field)
end

function Field:Name()
    return self._name
end

function Field:Description()
    return self._description
end

function Field:WithDescription(desc)
    self._description = desc
    return self
end

return Field
```

Also create `dslua/core/init.lua`:

```lua
local M = {}

M.Field = require("dslua.core.field")

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/core/field_spec.lua -v`
Expected: PASS (3 tests passing)

**Step 5: Commit**

```bash
git add dslua/core/ specs/core/
git commit -m "feat(core): implement Field type with name and description

Add Field type as foundational building block for Signatures.
Supports fluent chaining via WithDescription() method.

Tests: 3 passing (name creation, description, fluent chaining)"
```

---

## Task 2: Create Signature Type (Input/Output Contract)

**Files:**
- Create: `dslua/core/signature.lua`
- Modify: `dslua/core/init.lua`
- Create: `specs/core/signature_spec.lua`

**Step 1: Write the failing test**

Create `specs/core/signature_spec.lua`:

```lua
describe("Signature", function()
    local Field = require("dslua.core.field")

    it("should create signature with input and output fields", function()
        local Signature = require("dslua.core.signature")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        assert.is.equal(1, #signature:InputFields())
        assert.is.equal("question", signature:InputFields()[1]:Name())
        assert.is.equal(1, #signature:OutputFields())
        assert.is.equal("answer", signature:OutputFields()[1]:Name())
    end)

    it("should support multiple input and output fields", function()
        local Signature = require("dslua.core.signature")
        local signature = Signature.new(
            {Field.new("question"), Field.new("context")},
            {Field.new("answer"), Field.new("confidence")}
        )

        assert.is.equal(2, #signature:InputFields())
        assert.is.equal(2, #signature:OutputFields())
    end)

    it("should support instruction setting", function()
        local Signature = require("dslua.core.signature")
        local signature = Signature.new({}, {}):WithInstruction("Be concise")

        assert.is.equal("Be concise", signature:Instruction())
    end)

    it("should return self for fluent chaining", function()
        local Signature = require("dslua.core.signature")
        local signature = Signature.new({}, {})
        local result = signature:WithInstruction("Test")

        assert.is.equal(signature, result)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/core/signature_spec.lua -v`
Expected: FAIL with "module 'dslua.core.signature' not found"

**Step 3: Write minimal implementation**

Create `dslua/core/signature.lua`:

```lua
local Signature = {}
Signature.__index = Signature

function Signature.new(inputs, outputs)
    local self = {
        _inputs = inputs,
        _outputs = outputs,
        _instruction = "",
    }
    return setmetatable(self, Signature)
end

function Signature:InputFields()
    return self._inputs
end

function Signature:OutputFields()
    return self._outputs
end

function Signature:Instruction()
    return self._instruction
end

function Signature:WithInstruction(instruction)
    self._instruction = instruction
    return self
end

return Signature
```

Update `dslua/core/init.lua`:

```lua
local M = {}

M.Field = require("dslua.core.field")
M.Signature = require("dslua.core.signature")

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/core/signature_spec.lua -v`
Expected: PASS (4 tests passing)

**Step 5: Commit**

```bash
git add dslua/core/signature.lua dslua/core/init.lua specs/core/
git commit -m "feat(core): implement Signature type for input/output contracts

Signature defines the interface between inputs and outputs for modules.
Supports multiple fields and fluent instruction setting.

Tests: 4 passing (field access, multiple fields, instructions, chaining)"
```

---

## Task 3: Create Context Type (Request-Scoped Data)

**Files:**
- Create: `dslua/core/context.lua`
- Modify: `dslua/core/init.lua`
- Create: `specs/core/context_spec.lua`

**Step 1: Write the failing test**

Create `specs/core/context_spec.lua`:

```lua
describe("Context", function()
    it("should create context with no options", function()
        local Context = require("dslua.core.context")
        local ctx = Context.new()

        assert.is.equal(nil, ctx:LLM())
        assert.is.equal(0, #ctx:Trace())
    end)

    it("should create context with LLM", function()
        local Context = require("dslua.core.context")
        local mock_llm = {name = "test"}
        local ctx = Context.new({llm = mock_llm})

        assert.is.equal(mock_llm, ctx:LLM())
    end)

    it("should support creating derived context with LLM", function()
        local Context = require("dslua.core.context")
        local ctx1 = Context.new()
        local mock_llm = {name = "test"}
        local ctx2 = ctx1:WithLLM(mock_llm)

        assert.is.equal(nil, ctx1:LLM())
        assert.is.equal(mock_llm, ctx2:LLM())
        assert.is.not_equal(ctx1, ctx2)  -- New context created
    end)

    it("should store trace entries", function()
        local Context = require("dslua.core.context")
        local ctx = Context.new()
        ctx:AddTrace({step = "test", data = "value"})

        assert.is.equal(1, #ctx:Trace())
        assert.is.equal("test", ctx:Trace()[1].step)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/core/context_spec.lua -v`
Expected: FAIL with "module 'dslua.core.context' not found"

**Step 3: Write minimal implementation**

Create `dslua/core/context.lua`:

```lua
local Context = {}
Context.__index = Context

function Context.new(opts)
    opts = opts or {}
    local self = {
        _llm = opts.llm or nil,
        _trace = opts.trace or {},
        _metadata = opts.metadata or {},
    }
    return setmetatable(self, Context)
end

function Context:LLM()
    return self._llm
end

function Context:WithLLM(llm)
    local ctx = Context.new({
        llm = llm,
        trace = self._trace,
        metadata = self._metadata,
    })
    return ctx
end

function Context:Trace()
    return self._trace
end

function Context:AddTrace(entry)
    table.insert(self._trace, entry)
end

return Context
```

Update `dslua/core/init.lua`:

```lua
local M = {}

M.Field = require("dslua.core.field")
M.Signature = require("dslua.core.signature")
M.Context = require("dslua.core.context")

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/core/context_spec.lua -v`
Expected: PASS (4 tests passing)

**Step 5: Commit**

```bash
git add dslua/core/context.lua dslua/core/init.lua specs/core/
git commit -m "feat(core): implement Context for request-scoped data

Context carries LLM, trace, and metadata through module execution.
Supports immutable context creation via WithLLM() for derivation.

Tests: 4 passing (creation, LLM storage, derivation, trace tracking)"
```

---

## Task 4: Create Module Base Class

**Files:**
- Create: `dslua/modules/base.lua`
- Create: `dslua/modules/init.lua`
- Create: `specs/modules/base_spec.lua`

**Step 1: Write the failing test**

Create `specs/modules/base_spec.lua`:

```lua
describe("Module", function()
    local Field = require("dslua.core.field")
    local Signature = require("dslua.core.signature")

    it("should create module with signature", function()
        local Module = require("dslua.modules.base")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local module = Module.new(signature)

        assert.is.equal(signature, module:Signature())
    end)

    it("should support setting LLM", function()
        local Module = require("dslua.modules.base")
        local signature = Signature.new({}, {})
        local module = Module.new(signature)
        local mock_llm = {name = "test"}

        module:WithLLM(mock_llm)

        assert.is.equal(mock_llm, module:LLM())
    end)

    it("should return self for fluent chaining", function()
        local Module = require("dslua.modules.base")
        local signature = Signature.new({}, {})
        local module = Module.new(signature)
        local mock_llm = {name = "test"}

        local result = module:WithLLM(mock_llm)

        assert.is.equal(module, result)
    end)

    it("should error on Process() if not overridden", function()
        local Module = require("dslua.modules.base")
        local signature = Signature.new({}, {})
        local module = Module.new(signature)
        local ctx = require("dslua.core.context").new()

        assert.has_error(function()
            module:Process(ctx, {})
        end, "Process() must be implemented")
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/modules/base_spec.lua -v`
Expected: FAIL with "module 'dslua.modules.base' not found"

**Step 3: Write minimal implementation**

Create `dslua/modules/base.lua`:

```lua
local Module = {}
Module.__index = Module

function Module.new(signature)
    local self = {
        _signature = signature,
        _llm = nil,
        _config = {},
    }
    return setmetatable(self, Module)
end

function Module:Signature()
    return self._signature
end

function Module:LLM()
    return self._llm
end

function Module:WithLLM(llm)
    self._llm = llm
    return self
end

function Module:Process(ctx, input)
    error("Process() must be implemented by subclass")
end

function Module:Forward(ctx, input)
    return self:Process(ctx, input)
end

return Module
```

Create `dslua/modules/init.lua`:

```lua
local M = {}

M.Base = require("dslua.modules.base")

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/modules/base_spec.lua -v`
Expected: PASS (4 tests passing)

**Step 5: Commit**

```bash
git add dslua/modules/ specs/modules/
git commit -m "feat(modules): implement Module base class

Module provides the foundation for all DSPy modules with signature,
LLM attachment, and abstract Process() method.

Tests: 4 passing (creation, LLM setting, chaining, abstract error)"
```

---

## Task 5: Create OpenAI LLM Provider

**Files:**
- Create: `dslua/llms/base.lua`
- Create: `dslua/llms/providers/openai.lua`
- Create: `dslua/llms/init.lua`
- Create: `specs/llms/openai_spec.lua`

**Step 1: Write the failing test**

Create `specs/llms/openai_spec.lua`:

```lua
describe("OpenAI Provider", function()
    it("should create OpenAI provider with API key and model", function()
        local llms = require("dslua.llms")
        local llm = llms.OpenAI("test-key", "gpt-4")

        assert.is.equal("test-key", llm:APIKey())
        assert.is.equal("gpt-4", llm:Model())
        assert.is.equal("https://api.openai.com/v1", llm:BaseURL())
    end)

    it("should support custom base URL", function()
        local llms = require("dslua.llms")
        local llm = llms.OpenAI("test-key", "gpt-4", {
            base_url = "https://custom.example.com/v1"
        })

        assert.is.equal("https://custom.example.com/v1", llm:BaseURL())
    end)

    it("should build completion request body", function()
        local llms = require("dslua.llms")
        local llm = llms.OpenAI("test-key", "gpt-4")

        local body = llm:_buildRequestBody("Hello, world!", {temperature = 0.7})

        assert.is.equal("gpt-4", body.model)
        assert.is.equal(1, #body.messages)
        assert.is.equal("user", body.messages[1].role)
        assert.is.equal("Hello, world!", body.messages[1].content)
        assert.is.equal(0.7, body.temperature)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/llms/openai_spec.lua -v`
Expected: FAIL with "module 'dslua.llms' not found"

**Step 3: Write minimal implementation**

Create `dslua/llms/base.lua`:

```lua
local BaseLLM = {}
BaseLLM.__index = BaseLLM

function BaseLLM.new(config)
    return setmetatable({
        _api_key = config.api_key,
        _base_url = config.base_url,
        _model = config.model,
        _timeout = config.timeout or 30000,
    }, BaseLLM)
end

function BaseLLM:APIKey()
    return self._api_key
end

function BaseLLM:Model()
    return self._model
end

function BaseLLM:BaseURL()
    return self._base_url
end

function BaseLLM:Complete(ctx, prompt, opts)
    error("Complete() must be implemented by subclass")
end

return BaseLLM
```

Create `dslua/llms/providers/openai.lua`:

```lua
local BaseLLM = require("dslua.llms.base")
local OpenAI = {}
OpenAI.__index = OpenAI
setmetatable(OpenAI, {__index = BaseLLM})

function OpenAI.new(api_key, model, opts)
    opts = opts or {}
    local config = {
        api_key = api_key,
        model = model,
        base_url = opts.base_url or "https://api.openai.com/v1",
        timeout = opts.timeout,
    }
    local self = BaseLLM.new(config)
    setmetatable(self, OpenAI)
    return self
end

function OpenAI:Complete(ctx, prompt, opts)
    -- HTTP client integration will be added in later tasks
    error("HTTP integration not yet implemented")
end

function OpenAI:_buildRequestBody(prompt, opts)
    opts = opts or {}
    return {
        model = self._model,
        messages = {{role = "user", content = prompt}},
        temperature = opts.temperature or 0.7,
    }
end

return OpenAI
```

Create `dslua/llms/init.lua`:

```lua
local M = {}

function M.OpenAI(api_key, model, opts)
    return require("dslua.llms.providers.openai").new(api_key, model, opts)
end

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/llms/openai_spec.lua -v`
Expected: PASS (3 tests passing)

**Step 5: Commit**

```bash
git add dslua/llms/ specs/llms/
git commit -m "feat(llms): implement OpenAI provider base structure

Add OpenAI LLM provider with configuration and request building.
HTTP integration to be added in separate task after vendoring deps.

Tests: 3 passing (creation, custom URL, request body building)"
```

---

## Task 6: Implement Predict Module

**Files:**
- Create: `dslua/modules/predict.lua`
- Modify: `dslua/modules/init.lua`
- Create: `specs/modules/predict_spec.lua`

**Step 1: Write the failing test**

Create `specs/modules/predict_spec.lua`:

```lua
describe("Predict", function()
    local Field = require("dslua.core.field")
    local Signature = require("dslua.core.signature")
    local Context = require("dslua.core.context")

    it("should create predict with signature", function()
        local Predict = require("dslua.modules.predict")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local predict = Predict.new(signature)

        assert.is.equal(signature, predict:Signature())
    end)

    it("should build prompt from input and signature", function()
        local Predict = require("dslua.modules.predict")
        local signature = Signature.new(
            {Field.new("question", {desc = "The question"})},
            {Field.new("answer", {desc = "The answer"})}
        )
        local predict = Predict.new(signature)

        local prompt = predict:_buildPrompt({question = "What is 2+2?"})

        assert.is.truthy(string.find(prompt, "question"))
        assert.is.truthy(string.find(prompt, "What is 2+2?"))
    end)

    it("should use context LLM if available", function()
        local Predict = require("dslua.modules.predict")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local predict = Predict.new(signature)

        local mock_llm = {
            Complete = function(self, ctx, prompt, opts)
                return {answer = "42"}
            end
        }
        local ctx = Context.new({llm = mock_llm})

        local result = predict:Process(ctx, {question = "What is 6*7?"})

        assert.is.equal("42", result.answer)
    end)

    it("should use module LLM if context LLM not available", function()
        local Predict = require("dslua.modules.predict")
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local predict = Predict.new(signature)

        local mock_llm = {
            Complete = function(self, ctx, prompt, opts)
                return {answer = "Paris"}
            end
        }
        predict:WithLLM(mock_llm)
        local ctx = Context.new()

        local result = predict:Process(ctx, {question = "Capital of France?"})

        assert.is.equal("Paris", result.answer)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/modules/predict_spec.lua -v`
Expected: FAIL with "module 'dslua.modules.predict' not found"

**Step 3: Write minimal implementation**

Create `dslua/modules/predict.lua`:

```lua
local Base = require("dslua.modules.base")
local Predict = {}
Predict.__index = Predict
setmetatable(Predict, {__index = Base})

function Predict.new(signature)
    local self = Base.new(signature)
    setmetatable(self, Predict)
    return self
end

function Predict:Process(ctx, input)
    local llm = ctx:LLM() or self:LLM()
    if not llm then
        error("No LLM configured in module or context")
    end

    local prompt = self:_buildPrompt(input)
    local response = llm:Complete(ctx, prompt, {})

    return response
end

function Predict:_buildPrompt(input)
    local parts = {}

    for _, field in ipairs(self._signature:InputFields()) do
        local value = input[field:Name()]
        if value then
            table.insert(parts, string.format("%s: %s", field:Name(), tostring(value)))
        end
    end

    return table.concat(parts, "\n")
end

return Predict
```

Update `dslua/modules/init.lua`:

```lua
local M = {}

M.Base = require("dslua.modules.base")
M.Predict = require("dslua.modules.predict")

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/modules/predict_spec.lua -v`
Expected: PASS (4 tests passing)

**Step 5: Commit**

```bash
git add dslua/modules/predict.lua dslua/modules/init.lua specs/modules/
git commit -m "feat(modules): implement Predict module

Predict provides direct LLM prediction using signature-defined inputs.
Builds prompts from input fields and delegates to LLM:Complete().

Tests: 4 passing (creation, prompt building, context LLM, module LLM)"
```

---

## Task 7: Create Main Package Entry Point

**Files:**
- Create: `dslua/init.lua`
- Create: `specs/integration_spec.lua`

**Step 1: Write the failing test**

Create `specs/integration_spec.lua`:

```lua
describe("Package Integration", function()
    it("should expose all core types from main package", function()
        local dslua = require("dslua")

        assert.is.truthy(dslua.Field)
        assert.is.truthy(dslua.Signature)
        assert.is.truthy(dslua.Context)
        assert.is.truthy(dslua.Predict)
        assert.is.truthy(dslua.llms)
    end)

    it("should support complete end-to-end flow", function()
        local dslua = require("dslua")

        -- Create signature
        local signature = dslua.Signature.new(
            {dslua.Field.new("question")},
            {dslua.Field.new("answer")}
        )

        -- Create module
        local predict = dslua.Predict.new(signature)

        -- Create mock LLM
        local mock_llm = {
            Complete = function(self, ctx, prompt, opts)
                return {answer = "42"}
            end
        }

        -- Create context with LLM
        local ctx = dslua.Context.new({llm = mock_llm})

        -- Execute
        local result = predict:Process(ctx, {question = "What is 6*7?"})

        assert.is.equal("42", result.answer)
    end)

    it("should create OpenAI LLM via factory", function()
        local dslua = require("dslua")
        local llm = dslua.llms.OpenAI("test-key", "gpt-4")

        assert.is.equal("gpt-4", llm:Model())
        assert.is.equal("test-key", llm:APIKey())
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/integration_spec.lua -v`
Expected: FAIL with "module 'dslua' not found"

**Step 3: Write minimal implementation**

Create `dslua/init.lua`:

```lua
local M = {}

-- Core types
M.Field = require("dslua.core.field")
M.Signature = require("dslua.core.signature")
M.Context = require("dslua.core.context")

-- Modules
M.Predict = require("dslua.modules.predict")

-- LLM providers
M.llms = require("dslua.llms")

return M
```

**Step 4: Run test to verify it passes**

Run: `busted specs/integration_spec.lua -v`
Expected: PASS (3 tests passing)

**Step 5: Commit**

```bash
git add dslua/init.lua specs/
git commit -m "feat(package): create main entry point with all public APIs

Expose core types, modules, and LLM providers through main package.
Supports end-to-end integration flows.

Tests: 3 passing (API exposure, end-to-end flow, LLM factory)"
```

---

## Task 8: Add CLI Skeleton

**Files:**
- Create: `cli/dslua.lua`
- Create: `specs/cli_spec.lua`

**Step 1: Write the failing test**

Create `specs/cli_spec.lua`:

```lua
describe("CLI", function()
    it("should load without errors", function()
        local cli = require("cli.dslua")

        assert.is.truthy(cli)
        assert.is.function(cli.run)
    end)
end)
```

**Step 2: Run test to verify it fails**

Run: `busted specs/cli_spec.lua -v`
Expected: FAIL with "module 'cli.dslua' not found"

**Step 3: Write minimal implementation**

Create `cli/dslua.lua`:

```lua
#!/usr/bin/env luajit

local dslua = require("dslua")

local commands = {}

function commands.list()
    print("Available optimizers:")
    print("  - mipro: TPE-based prompt optimization (coming soon)")
    print("  - bootstrap: Few-shot demonstration learning (coming soon)")
    print("  - gekko: Evolutionary prompt search (coming soon)")
end

function commands.help()
    print([[dslua - DSPy for Lua

Usage: dslua <command> [options]

Commands:
  list              List available optimizers
  help              Show this help message

More commands coming soon!]])
end

local function main()
    local arg = arg or {}

    if #arg == 0 then
        commands.help()
        return
    end

    local cmd = arg[1]

    if commands[cmd] then
        commands[cmd](select(2, table.unpack(arg)))
    else
        print("Unknown command: " .. cmd)
        commands.help()
        os.exit(1)
    end
end

return {
    run = main,
    commands = commands,
}
```

**Step 4: Run test to verify it passes**

Run: `busted specs/cli_spec.lua -v`
Expected: PASS (1 test passing)

Make CLI executable:
```bash
chmod +x cli/dslua.lua
```

**Step 5: Commit**

```bash
git add cli/ specs/
git commit -m "feat(cli): add skeleton with list and help commands

CLI provides basic interface for dslua with extensible command system.
More commands will be added as features are implemented.

Tests: 1 passing (module loads correctly)"
```

---

## Task 9: Update README with Usage Examples

**Files:**
- Modify: `README.md`

**Step 1: Update README with current functionality**

Replace the content of `README.md` with updated examples showing working features:

```markdown
# dslua

DSPy for Lua - LLM orchestration framework with composable modules, agents, and optimizers.

**Status:** 🚧 Under Active Development (Phase 1)

This is a Lua port of [DSPy-Go](https://github.com/postfix/dspy-go), bringing systematic prompt engineering and automated reasoning capabilities to Lua applications through LuaJIT 2.1+.

## What is dslua?

dslua is a native Lua implementation of the DSPy framework for building reliable LLM applications. Use composable modules and workflows to orchestrate LLM calls with minimal overhead.

## Current Status (Phase 1)

✅ **Implemented:**
- Core abstractions: Field, Signature, Context, Module base
- Predict module for direct LLM prediction
- OpenAI provider structure (HTTP integration pending)

🚧 **In Progress:**
- HTTP client integration for OpenAI
- Anthropic and Gemini providers
- ChainOfThought and ReAct modules

## Quick Start

### Installation

```bash
git clone https://github.com/postfix/dslua.git
cd dslua
luajit --version  # Ensure LuaJIT 2.1+
```

### Programming API

```lua
local dslua = require("dslua")

-- Create signature (input/output contract)
local signature = dslua.Signature.new(
    {dslua.Field.new("question")},
    {dslua.Field.new("answer")}
)

-- Create predict module
local predict = dslua.Predict.new(signature)

-- Create mock LLM (replace with real OpenAI when HTTP is integrated)
local mock_llm = {
    Complete = function(self, ctx, prompt, opts)
        -- This would call OpenAI API
        return {answer = "42"}
    end
}

-- Create context
local ctx = dslua.Context.new({llm = mock_llm})

-- Execute
local result = predict:Process(ctx, {question = "What is 6*7?"})
print(result.answer)  -- 42
```

### CLI

```bash
./cli/dslua list    # List available optimizers
./cli/dslua help    # Show help
```

## Requirements

- **LuaJIT 2.1+** - Required for performance and FFI support

## Documentation

- [DESIGN.md](DESIGN.md) - Complete architecture and implementation roadmap
- [Phase 1 Plan](docs/plans/2026-01-28-phase1-core-abstractions.md) - Detailed implementation steps

## Progress

- [x] Phase 1: Core abstractions (Field, Signature, Context, Module, Predict)
- [ ] Phase 1: HTTP client integration
- [ ] Phase 2: ChainOfThought, ReAct, Refine modules
- [ ] Phase 3: Agents and Advanced Features
- [ ] Phase 4: Optimizers

See [DESIGN.md](DESIGN.md) for detailed implementation phases.

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by [DSPy](https://github.com/stanfordnlp/dspy) from Stanford
- Ported from [DSPy-Go](https://github.com/postfix/dspy-go)
```

**Step 2: Verify README is accurate**

Check that all code examples in README are correct and tested.

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: update README with Phase 1 status and working examples

Update documentation to reflect current implementation state.
Include working code examples for core abstractions."
```

---

## Task 10: Run Full Test Suite and Verify

**Files:**
- All test files

**Step 1: Run complete test suite**

Run: `busted -v`
Expected: All tests passing

**Step 2: Check test coverage**

```bash
luajit -e "print('Test suite status:')"
busted --coverage
```

**Step 3: Verify package can be loaded**

```bash
luajit -e "local dslua = require('dslua'); print('Package loaded successfully')"
```

**Step 4: Update DESIGN.md with Phase 1 completion status**

Add checkpoint to DESIGN.md:

```markdown
## Implementation Progress

### Phase 1: Foundation ✅ COMPLETE
- [x] Core abstractions (Field, Signature, Context, Module)
- [x] Predict module
- [x] OpenAI provider structure
- [x] CLI skeleton
- [x] Test infrastructure with busted
- [x] Main package entry point

### Phase 2: Core Modules (Next)
- [ ] HTTP client integration
- [ ] ChainOfThought module
- [ ] ReAct module
- [ ] Refine module
- [ ] Anthropic provider
- [ ] Gemini provider
```

**Step 5: Final Phase 1 commit**

```bash
git add DESIGN.md
git commit -m "docs: mark Phase 1 as complete in DESIGN.md

All core abstractions implemented and tested.
Ready to begin Phase 2 with HTTP integration and advanced modules."
```

---

## Summary

Phase 1 establishes the foundation for dslua with:

✅ **Core Types:** Field, Signature, Context
✅ **Module System:** Base class and Predict implementation
✅ **LLM Provider:** OpenAI structure (HTTP pending)
✅ **Testing:** Comprehensive test coverage with busted
✅ **Integration:** End-to-end package usage
✅ **CLI:** Basic command structure

**Test Coverage:** 27 tests across all components
**Commits:** 10 focused commits with clear messages
**Next Phase:** HTTP client integration → ChainOfThought → ReAct → More providers
