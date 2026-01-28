# dslua Design Document

**Date:** 2026-01-28
**Status:** Phase 2 Complete ✅
**Target:** Complete port of DSPy-Go to Lua

## Overview

**dslua** is a Lua port of the DSPy-Go framework, bringing systematic prompt engineering and automated LLM orchestration to the Lua ecosystem. The project targets LuaJIT 2.1+ for optimal performance and provides complete feature parity with DSPy-Go.

**Motivation:** General purpose scripting - using Lua as a lightweight language for LLM applications.

**Repository:** https://github.com/postfix/dslua

## Technical Decisions

### Platform and Ecosystem
- **Target Platform:** LuaJIT 2.1+ (for performance and JIT compilation)
- **Architecture Strategy:** Lua-idiomatic adaptation while maintaining overall DSPy structure
- **Package Management:** Vendor everything (batteries-included) for zero-install setup
- **Module System:** Hierarchical package structure (`require('dslua.modules.predict')`)

### Code Organization
- **Structure:** Mirrors Go's `pkg/` hierarchy as `dslua/` package namespace
- **OOP Approach:** Object-oriented with metatables (LuaJIT optimizes metatable lookups)
- **Naming:** Lua conventions (snake_case) while preserving DSPy terminology

## Project Structure

```
dslua/
├── .github/workflows/ci.yml      # LuaJIT testing, busted test runner
├── cli/dslua.lua                  # Zero-code CLI for optimizers
├── deps/                          # Vendored dependencies
│   ├── dkjson/                    # JSON encoding/decoding
│   ├── lua-http/                  # HTTP client for LLM APIs
│   └── busted/                    # Testing framework
├── docs/content/                  # Documentation (mirrors dspy-go/docs)
├── examples/                      # Usage examples
│   ├── agents/
│   ├── modules/
│   ├── tools/
│   └── optimizers/
├── dslua/                         # Main package root
│   ├── init.lua                   # Package entry point
│   ├── core/
│   │   ├── signature.lua
│   │   ├── context.lua
│   │   └── llm_config.lua
│   ├── modules/
│   │   ├── predict.lua
│   │   ├── chain_of_thought.lua
│   │   ├── react.lua
│   │   ├── rlm.lua
│   │   ├── refine.lua
│   │   └── parallel.lua
│   ├── agents/
│   │   ├── react_agent.lua
│   │   └── ace.lua
│   ├── llms/
│   │   ├── providers/
│   │   │   ├── openai.lua
│   │   │   ├── anthropic.lua
│   │   │   ├── gemini.lua
│   │   │   └── ollama.lua
│   │   └── base.lua
│   ├── tools/
│   │   ├── registry.lua
│   │   └── chaining.lua
│   ├── optimizers/
│   │   ├── mipro.lua
│   │   ├── gekko.lua
│   │   └── bootstrap.lua
│   └── structured/
│       └── json_adapter.lua
├── specs/                         # Test files (busted convention)
│   ├── core_spec.lua
│   ├── modules_spec.lua
│   └── integration_spec.lua
├── .lua-version                   # Specifies LuaJIT 2.1
├── .luacheckrc                   # Linter configuration
└── README.md
```

## Core Architecture

### 1. Core Abstractions

**Signature** - Defines input/output contracts for modules:

```lua
local signature = dslua.Signature.new(
    {dslua.Field.new("question", {desc = "Question to answer"})},
    {dslua.Field.new("answer", {desc = "Detailed answer"})}
)
signature:WithInstruction("Answer accurately and concisely.")
```

**Field** - Typed input/output descriptors with metadata.

**Context** - Request-scoped data carrier (similar to Go's context.Context):

```lua
local ctx = dslua.Context.new({
    llm = openai_llm,
    trace = {},
    metadata = {},
})
```

### 2. Module System

All modules inherit from `Module` base class using metatable inheritance:

```lua
local Module = {}
Module.__index = Module

function Module.new(signature)
    return setmetatable({
        _signature = signature,
        _llm = nil,
        _config = {},
    }, Module)
end

function Module:Process(ctx, input)
    error("Process() must be implemented by subclass")
end
```

**Predict** - Direct LLM prediction
**ChainOfThought** - Step-by-step reasoning with augmented prompts
**ReAct** - Reasoning + tool use with iterative loops
**RLM** - Large context exploration via REPL
**Refine** - Quality improvement through iteration
**Parallel** - Concurrent batch processing

### 3. LLM Provider System

Common interface with pluggable providers:

```lua
-- Base provider interface
function BaseLLM:Complete(ctx, prompt, opts)
    error("Complete() must be implemented")
end

-- Provider factory
local openai = dslua.llms.OpenAI("api-key", "gpt-4")
local anthropic = dslua.llms.Anthropic("api-key", "claude-3-sonnet")
local gemini = dslua.llms.Gemini("api-key", "gemini-pro")
local ollama = dslua.llms.Ollama("llama3.1")
```

Providers use vendored HTTP client (`deps/lua-http`) for API calls.

### 4. Agent Framework

**ReAct Agent** - Autonomous reasoning with tool use:

```lua
local agent = dslua.agents.ReActAgent.new(module, {
    tools = {search_tool, calculator},
    max_steps = 20,
})

local result = agent:Run(ctx, {goal = "Find the population of Tokyo"})
```

**ACE (Autonomous Cognitive Entity)** - Self-improving agents with learning:

```lua
local ace = dslua.agents.ACE.new(module, {
    tools = tools,
    learning_rate = 0.1,
})

local result = ace:Run(ctx, goal)
-- ACE evaluates performance and updates internal policy
```

### 5. Tool System

**Tool Base Class** - Executable units with schema validation:

```lua
local search_tool = dslua.Tool.new("search", {
    description = "Search the web",
    func = function(args)
        return web_search(args.query)
    end,
    schema = {query = "string"},
})
```

**Smart Registry** with Bayesian selection:

```lua
local registry = dslua.tools.Registry.new()
registry:Register(search_tool)

-- Selects best tool based on success history and query similarity
local tool = registry:Select("find information about X", {
    strategy = "bayesian",
})

local result = tool:Execute({query = "X"})

registry:RecordUsage(tool._name, success)  -- Updates success rate
```

**Tool Chaining** - Multi-step pipeline composition:

```lua
local chain = chaining:BuildChain("research and summarize topic")
local result = chain({topic = "quantum computing"})
```

### 6. Optimizers

**Optimizer Base** - Common interface for prompt tuning:

```lua
function Optimizer:Compile(ctx, num_trials)
    error("Compile() must be implemented")
end

function Optimizer:Evaluate(ctx, program)
    -- Run evaluation on dataset
    local total = 0
    for _, example in ipairs(self._dataset) do
        local result = program:Process(ctx, example.input)
        total = total + self._metric(result, example.output)
    end
    return total / #self._dataset
end
```

**BootstrapFewShot** - Few-shot demonstration learning:

1. Sample training examples from dataset
2. Generate demonstrations using base module
3. Create optimized program with demonstration prompts
4. Evaluate on validation set

**MIPRO** - TPE-based optimization (Tree-structured Parzen Estimator)
**GEPA** - Evolutionary prompt search
**SIMBA** - Introspective optimization
**COPRO** - Cooperative optimization

### 7. Structured Output

**JSON Adapter** - Enforces schema compliance:

```lua
local module = dslua.Predict.new(signature)
local structured = dslua.structured.WithStructuredOutput(module, {
    answer = "string",
    confidence = "number",
    sources = "table",
})

local result = structured:Process(ctx, input)
-- Guaranteed to match schema or error
```

Features:
- Schema injection into prompts
- JSON validation with retry on parse errors
- Type checking for all fields

### 8. CLI and REPL

**Zero-code CLI** for common tasks:

```bash
./dslua list                           # List all optimizers
./dslua try mipro --dataset gsm8k      # Test optimizer instantly
./dslua view session.jsonl --stats     # View RLM session logs
./dslua repl                           # Start interactive REPL
```

**Interactive REPL** with embedded DSLy context:

```lua
dslua> local cot = dslua.ChainOfThought.new(signature)
dslua> cot:Process(ctx, {question = "What is 2+2?"})
{
  reasoning = "2 + 2 equals 4",
  answer = "4"
}
```

## Testing Strategy

**Framework:** Busted (Lua testing framework)
**Location:** `specs/` directory (Busted convention)

Example test structure:

```lua
describe("Signature", function()
    it("should create signature with input/output fields", function()
        local signature = dslua.Signature.new(
            {dslua.Field.new("question")},
            {dslua.Field.new("answer")}
        )
        assert.is.same(1, #signature:InputFields())
    end)
end)
```

**Test Coverage:**
- Unit tests for each module
- Integration tests with mock LLMs
- Provider tests with real APIs (optional/configured)
- Benchmark tests for performance validation

## Error Handling

Custom error types with contextual information:

```lua
local Errors = require("dslua.errors")

error(Errors.ModuleError("Failed to process", "ChainOfThought"))
error(Errors.LLMError("API rate limit exceeded", "OpenAI"))
error(Errors.ValidationError("Invalid type", "answer"))
```

Each error type includes:
- Error type classification
- Source context (module name, provider)
- Helpful error messages with stack traces

## Implementation Progress

### Phase 1: Foundation ✅ COMPLETE (2026-01-28)
- [x] Core abstractions (Field, Signature, Context, Module)
- [x] Predict module
- [x] OpenAI provider structure (HTTP pending)
- [x] CLI skeleton
- [x] Test infrastructure with busted
- [x] Main package entry point
- [x] Documentation updated

**Results:**
- 26 tests passing (100% pass rate)
- 9 focused commits
- All core abstractions working
- Ready for Phase 2

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
- [x] Ollama provider for local testing
- [x] Package exports updated

**Results:**
- 59 tests passing (100% pass rate)
- 12 focused commits
- All providers functional with real APIs
- All advanced modules working
- Ready for Phase 3

### Phase 3: Agents and Advanced Features (Pending)
- [ ] ReAct agent with tool use
- [ ] ACE framework with learning
- [ ] Tool chaining and composition
- [ ] Structured output (JSON adapter)

### Phase 4: Optimizers and Polish (Pending)
- [ ] BootstrapFewShot optimizer
- [ ] MIPRO (TPE-based optimization)
- [ ] GEPA (evolutionary) and SIMBA
- [ ] Documentation and examples
- [ ] Performance benchmarking

---

## Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
- Repository setup, GitHub Actions CI
- Vendored dependencies: dkjson, lua-http, busted
- Core abstractions: Signature, Field, Context, Module base
- OpenAI provider only (for initial testing)
- Basic Predict module

### Phase 2: Core Modules (Weeks 3-4)
- ChainOfThought, ReAct, Refine modules
- Anthropic and Gemini providers
- Tool base class and simple registry
- Comprehensive test coverage for core

### Phase 3: Agents and Advanced Features (Weeks 5-7)
- ReAct agent with tool use
- ACE framework with learning
- Tool chaining and composition
- Structured output (JSON adapter)
- CLI interface implementation

### Phase 4: Optimizers and Polish (Weeks 8-10)
- BootstrapFewShot optimizer
- MIPRO (TPE-based optimization)
- GEPA (evolutionary) and SIMBA
- Documentation and examples
- Performance benchmarking

## Key Implementation Considerations

### 1. LuaJIT FFI
Use FFI for critical paths:
- HTTP request handling
- JSON parsing (cjson via FFI)
- High-frequency operations

### 2. Coroutines
Leverage Lua coroutines for async patterns:
- Concurrent module execution (Parallel)
- Streaming responses
- Non-blocking I/O operations

### 3. Module Loading
Lazy-load modules with `require()`:
- Fast startup time
- Memory efficiency
- Optional feature loading

### 4. Backward Compatibility
Design API to work with Lua 5.1 if needed:
- Avoid `//` operator (use `math.floor`)
- Avoid `goto` statements
- Use table unpack carefully (compat layer)

### 5. Performance Optimization
- Profile with LuaJIT's built-in profiler
- Use trace compilation hints (JIT pragmas)
- Minimize table allocations in hot paths
- Cache metatable lookups where appropriate

## Dependencies (Vendored)

**Required:**
- `dkjson` - JSON encoding/decoding
- `lua-http` - HTTP client for LLM APIs
- `busted` - Testing framework
- `argparse` - CLI argument parsing

**Optional:**
- `cjson` - Faster JSON via LuaJIT FFI
- `luasocket` - Alternative HTTP backend
- `inspect` - Pretty printing for REPL

## Documentation

Structure mirrors dspy-go documentation:
- Getting Started Guide
- Core Concepts (Signatures, Modules, Programs)
- Building Agents (ReAct, ACE, Memory)
- Tool Management (Registry, Chaining, Composition)
- Optimizers (MIPRO, Bootstrap, GEPA, SIMBA)
- API Reference (auto-generated from annotations)
- Examples (ported from dspy-go/examples)

## Success Criteria

1. **Feature Parity:** All DSPy-Go modules, agents, and optimizers implemented
2. **Performance:** Within 2x of Go performance (LuaJIT is fast)
3. **Test Coverage:** >80% code coverage with Busted
4. **Documentation:** Complete guides and API reference
5. **Examples:** All major examples from dspy-go ported
6. **CLI:** Zero-code interface for common workflows

## Migration from DSPy-Go

For developers familiar with DSPy-Go:
- Same module names and concepts
- Similar API patterns (method chaining, Process())
- Lua idioms replace Go patterns (tables vs structs, metatables vs interfaces)
- Hierarchical package structure matches Go's pkg layout

Example comparison:

```go
// Go
signature := core.NewSignature(
    []core.InputField{{Field: core.NewField("question")}},
    []core.OutputField{{Field: core.NewField("answer")}},
)
cot := modules.NewChainOfThought(signature)
result, _ := cot.Process(context.Background(), map[string]interface{}{
    "question": "What is 2+2?",
})
```

```lua
-- Lua
local signature = dslua.Signature.new(
    {dslua.Field.new("question")},
    {dslua.Field.new("answer")}
)
local cot = dslua.ChainOfThought.new(signature)
local result = cot:Process(ctx, {question = "What is 2+2?"})
```

## Conclusion

dslua brings the power of DSPy to the Lua ecosystem with complete feature parity and LuaJIT performance. The hierarchical package structure, metatable-based OOP, and vendored dependencies make it easy to adopt for general-purpose LLM scripting while maintaining familiarity for DSPy-Go developers.
