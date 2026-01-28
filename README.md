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
