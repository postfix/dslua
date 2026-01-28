# dslua

DSPy for Lua - LLM orchestration framework with composable modules, agents, and optimizers.

**Status:** ✅ Phase 3 Complete - ReAct Agent Framework

This is a Lua port of [DSPy-Go](https://github.com/postfix/dspy-go), bringing systematic prompt engineering and automated reasoning capabilities to Lua applications through LuaJIT 2.1+.

## What is dslua?

dslua is a native Lua implementation of the DSPy framework for building reliable LLM applications. Use composable modules and workflows to orchestrate LLM calls with minimal overhead.

## Current Status (Phase 3 Complete)

✅ **Implemented:**
- Core abstractions: Field, Signature, Context, Module base
- Predict module for direct LLM prediction
- ChainOfThought module with reasoning extraction
- ReAct module with tool use and iteration
- Refine module with self-critique
- **ReActAgent Framework** with enhanced context and retry logic
- **Tool Registry** for centralized tool management
- **Built-in tools** (Calculator, StringHelper, SearchTool)
- HTTP client integration (lua-http + dkjson)
- OpenAI provider with real API calls
- Anthropic provider (Claude API)
- Gemini provider (Google API)
- Ollama provider for local testing
- **125 tests passing** (100% pass rate)

🚧 **In Progress:**
- Advanced optimizers (MIPRO, BootstrapFewShot, etc.)
- ACE framework with learning

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

-- Create LLM provider (OpenAI, Anthropic, Gemini, Ollama)
local llm = dslua.llms.OpenAI("your-api-key", "gpt-3.5-turbo")

-- Create signature (input/output contract)
local signature = dslua.Signature.new(
    {dslua.Field.new("question")},
    {dslua.Field.new("answer")}
)

-- Create ChainOfThought module for reasoning
local cot = dslua.ChainOfThought.new(signature)

-- Create context with LLM
local ctx = dslua.Context.new({llm = llm})

-- Execute with reasoning
local result = cot:Process(ctx, {question = "What is 6*7?"})
print(result.answer)     -- "42"
print(result.reasoning)  -- Step-by-step reasoning
```

### Using ReActAgent with Tools

```lua
local dslua = require("dslua")

-- Create tool registry and register tools
local registry = dslua.ToolRegistry.new()

-- Add built-in calculator tool
local Calculator = require("dslua.tools.builtin.calculator")
registry:Register("calculator", Calculator.new(), {
    description = "Performs arithmetic operations",
    category = "basic"
})

-- Create ReActAgent
local agent = dslua.ReActAgent.new(signature, {
    tool_registry = registry,
    max_iterations = 10,
    output_mode = "structured"
})

agent:WithLLM(llm)

-- Execute with tool use
local result = agent:Execute(ctx, "Calculate (15+27)*2")

print(result.answer)         -- "84"
print(result.tool_usage)     -- {calculator = 3}
print(result.iterations)     -- 4
print(result.summary)        -- Conversation summary
```

### Creating Custom Tools

```lua
local Tool = require("dslua.tools.base")

local weather_tool = Tool.new("weather", {
    description = "Get current weather for a city",
    func = function(args)
        -- Implement weather lookup
        return string.format("Weather in %s: 22°C, Sunny", args.city)
    end
})

registry:Register("weather", weather_tool, {
    description = "Get weather information",
    category = "utility",
    parameters = {"city"}
})
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
- [x] Phase 2: HTTP Integration and Advanced Modules
- [x] Phase 3: ReAct Agent Framework with Tool Registry
- [ ] Phase 4: Optimizers

See [DESIGN.md](DESIGN.md) for detailed implementation phases.

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by [DSPy](https://github.com/stanfordnlp/dspy) from Stanford
- Ported from [DSPy-Go](https://github.com/postfix/dspy-go)
