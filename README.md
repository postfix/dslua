# dslua

DSPy for Lua - LLM orchestration framework with composable modules, agents, and optimizers.

**Status:** 🚧 Under Active Development

This is a Lua port of [DSPy-Go](https://github.com/postfix/dspy-go), bringing systematic prompt engineering and automated reasoning capabilities to Lua applications through LuaJIT 2.1+.

## What is dslua?

dslua is a native Lua implementation of the DSPy framework for building reliable LLM applications. Use composable modules and workflows to orchestrate LLM calls with minimal overhead.

## Key Features

| Feature | Description |
|---------|-------------|
| **Modular Architecture** | Compose simple, reusable components into complex applications |
| **Multiple LLM Providers** | OpenAI, Anthropic, Google Gemini, Ollama, and more |
| **Advanced Modules** | Predict, ChainOfThought, ReAct, RLM, Refine, Parallel |
| **Intelligent Agents** | ReAct patterns, ACE framework for self-improving agents |
| **Smart Tool Management** | Bayesian selection, chaining, composition |
| **Quality Optimizers** | GEPA, MIPRO, SIMBA, BootstrapFewShot |
| **Structured Output** | JSON structured output with schema validation |

## Installation

```bash
git clone https://github.com/postfix/dslua.git
cd dslua
```

## Quick Start

### CLI (Zero Code)

```bash
./cli/dslua list                           # See all optimizers
./cli/dslua try mipro --dataset gsm8k      # Test optimizer instantly
./cli/dslua view session.jsonl --stats     # View RLM session logs
```

### Programming

```lua
local dslua = require("dslua")

-- Configure LLM
local openai = dslua.llms.OpenAI("your-api-key", "gpt-4")

-- Create signature and module
local signature = dslua.Signature.new(
    {dslua.Field.new("question")},
    {dslua.Field.new("answer")}
)
local cot = dslua.ChainOfThought.new(signature)

-- Execute
local ctx = dslua.Context.new({llm = openai})
local result = cot:Process(ctx, {question = "What is the capital of France?"})
print(result.answer)  -- Paris
```

## Requirements

- **LuaJIT 2.1+** - Required for performance and FFI support
- No external package manager needed (dependencies are vendored)

## Documentation

See [DESIGN.md](DESIGN.md) for the complete architecture and implementation roadmap.

## Progress

This project is under active development. The core architecture is designed, with implementation planned in phases:

- [x] Complete design document
- [ ] Phase 1: Foundation (Core abstractions, OpenAI provider, Predict module)
- [ ] Phase 2: Core Modules (ChainOfThought, ReAct, Refine, other providers)
- [ ] Phase 3: Agents and Advanced Features (ReAct agent, ACE, tools, CLI)
- [ ] Phase 4: Optimizers and Polish (MIPRO, GEPA, SIMBA, documentation)

See [DESIGN.md](DESIGN.md) for detailed implementation phases.

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by [DSPy](https://github.com/stanfordnlp/dspy) from Stanford
- Ported from [DSPy-Go](https://github.com/postfix/dspy-go)
