# dslua: DSPy Framework for Lua

**DSPy for LuaJIT 2.1+** - Systematic prompt engineering with compiled performance.

[![Tests](https://img.shields.io/badge/tests-1022%20passing-brightgreen)](https://github.com/postfix/dslua)
[![Parity](https://img.shields.io/badge/parity-DSPy--Go~100%25-brightgreen)](https://github.com/postfix/dslua)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**Status:** Production-ready with MIPRO optimizer and ACE learning framework | **100% feature parity** with DSPy-Go

---

## 🎯 What is dslua?

dslua brings the **systematic prompt engineering** paradigm of [DSPy](https://github.com/stanfordnlp/dspy) to Lua. Unlike traditional prompt engineering, dslua allows you to:

- **Declare** program behavior with signatures and modules
- **Compile** programs with automatic optimization
- **Learn** from demonstrations and execution outcomes
- **Optimize** prompts using Bayesian methods (MIPRO)

### Why Lua?

- **Performance:** LuaJIT compiles to native code, 10-50x faster than Python
- **Embedding:** Ideal for game engines, embedded systems, high-performance servers
- **Simplicity:** Minimal syntax, fast startup, low memory footprint
- **Integration:** Easy FFI to C/C++ libraries and native performance

---

## ✨ Key Features

### 🤖 LLM Abstractions

**Modules:**
- `Predict` - Direct LLM prediction
- `ChainOfThought` - Step-by-step reasoning
- `ReAct` - Tool use with reasoning
- `FewShot` - Demonstration-based prompts
- `Refine` - Iterative quality improvement
- `StructuredPredict` - Structured output with JSON schema validation
- **`Parallel`** - Concurrent batch processing ✨ NEW
  - Multi-worker batch processing for improved throughput
  - Timeout handling and automatic retry with exponential backoff
  - Progress tracking and statistics
  - Map, Filter, ForEach operations
  - 30 tests passing
- **`Retrieve`** - Retrieval-Augmented Generation (RAG) ✨ NEW
  - Vector similarity search with cosine similarity
  - BM25 keyword ranking algorithm
  - Hybrid retrieval combining multiple strategies
  - Custom formatting and metadata tracking
  - 25 tests passing
- **`RLM`** - Retrieve Language Model (Context Exploration) ✨ NEW
  - Multi-pass iterative context retrieval
  - Query refinement and expansion
  - RLMRetriever with automatic query expansion
  - ContextBuilder (sequential, clustered, hierarchical formats)
  - 21 tests passing

### 🔧 Tool Chaining

**Tool Composition:**
- **`ToolChain`** - Sequential tool execution with output passing ✨ NEW
- **`ToolParallel`** - Concurrent tool execution with merge strategies ✨ NEW
- **`ToolCondition`** - Conditional branching based on input ✨ NEW
- **`ToolLoop`** - Repeated execution with stop conditions ✨ NEW
- **`CompositeTool`** - Combine multiple tools into single interface ✨ NEW
- **`BayesianSelector`** - Smart tool selection with Thompson Sampling ✨ NEW
- 29 tests passing

**MCP Integration:**
- **`MCP Client`** - Model Context Protocol support ✨ NEW
  - Connection management and initialization
  - Resource listing and reading
  - Tool calling and prompt management
  - JSON-RPC 2.0 protocol
  - 22 tests passing

**Evaluation & Metrics:**
- **`Metrics Module`** - Comprehensive evaluation framework ✨ NEW
  - Accuracy, precision, recall, F1-score, confusion matrix
  - ROUGE-L, BLEU, Jaccard similarity for text
  - Latency statistics, throughput, cost estimation
  - Error analysis, metric aggregation
  - 51 tests passing
- **`Session Logger`** - Execution trace analysis ✨ NEW
  - Session logging and persistence
  - Event tracking with timestamps
  - Timeline and issue views
  - 25 tests passing

**CLI Interface:**
- **`try` Command** - Instant optimizer testing ✨ NEW
  - Register datasets and optimizers
  - Parse command-line arguments
  - Format and display results
  - 26 tests passing
- **`REPL`** - Interactive exploration environment ✨ NEW
  - Expression evaluation with =expr syntax
  - Lua code execution
  - Command system (.help, .vars, .history, .load, .save)
  - Multiline input support
  - History management
  - 23 tests passing

**LLM Providers:**
- `Anthropic` - Claude API support
- `OpenAI` - GPT models
- `Gemini` - Google Gemini
- `Ollama` - Local models
- **`LlamaCPP`** - Local inference server ✨ NEW
  - Chat format support
  - Caching for efficiency
  - Health checks, tokenization
  - 21 tests passing

**Optimizers:**
- `BootstrapFewShot` - Random subset optimization
- **`MIPRO`** - Multi-step Improvement with PRompt Optimization
  - Tree-structured Parzen Estimator (TPE) for Bayesian optimization
  - Automatic hyperparameter search
  - Multi-objective optimization (accuracy, latency, custom metrics)
  - 47 tests passing
- **`SIMBA`** - Similarity-Based Bootstrap ✨ NEW
  - Jaccard similarity for demonstration selection
  - Diversity optimization with greedy selection
  - Temperature-based refinement with annealing
  - Similarity matrix and diversity analysis
  - 23 tests passing
- **`GEPA`** - Greedy Ensemble Prompt Augmentation ✨ NEW
  - Ensemble of few-shot models with diverse demonstrations
  - Multiple aggregation strategies (majority vote, weighted, confidence)
  - Greedy search for optimal ensemble configuration
  - Ensemble analysis and diversity metrics
  - 28 tests passing
- **`COPRO`** - Coordinate Descent Prompt Optimization ✨ NEW
  - Iterative improvement with add, remove, replace, swap operations
  - Temperature-based search with simulated annealing
  - Early stopping for optimization efficiency
  - Optimization path analysis and tracking
  - 29 tests passing

### 🧠 Learning Agents

**ACE (Autonomous Cognitive Entity):**
- **Phase 1:** Rule-based decision engine with salience
- **Phase 2:** Learning from demonstrations (margin-based)
- **Phase 3:** Pattern mining & outcome feedback ✨ NEW
  - Temporal credit assignment across multi-step executions
  - Threshold learning & adaptation
  - Online learning from execution outcomes
  - 87 tests passing

**Multi-Agent Coordination:**
- **`A2A Protocol`** - Agent-to-Agent communication ✨ NEW
  - Point-to-point messaging
  - Request-response patterns
  - Broadcast and multicast
  - Custom routing and filtering
  - Message queues with handlers
  - Protocol metrics and logging
  - 34 tests passing

### 📈 Performance

**Benchmarking Suite:**
- **`Benchmark`** - Measure execution time and throughput ✨ NEW
- **`Comparison`** - Compare multiple implementations ✨ NEW
- **`Suite`** - Organized benchmark collections ✨ NEW
- **`Profiler`** - Workflow phase analysis ✨ NEW
- **`MemoryMonitor`** - Memory tracking ✨ NEW
- - 35 tests passing

### 📊 Structured Output

- JSON Schema validation
- Auto-retry on validation failure
- JSON repair for minor errors
- Provenance tracking (strict/repaired/retried)
- **XML Adapter** - Parse and generate XML with schema validation ✨ NEW
  - Schema-based parsing and generation
  - Repair and ignore error modes
  - Support for arrays, objects, and nested structures
  - 23 tests passing

---

## 🚀 Quick Start

### Basic Program

```lua
local Predict = require("dslua.modules.predict")
local Signature = require("dslua.core.signature")
local Field = require("dslua.core.field")

-- Define signature
local sig = Signature.new(
  {Field.new("question")},
  {Field.new("answer")}
)

-- Create program
local program = Predict.new(sig)

-- Execute
local result = program:Process(ctx, {
  question = "What is 2+2?"
})
```

### Optimization with MIPRO

```lua
local MIPRO = require("dslua.optimizers.mipro")

local optimizer = MIPRO.new(program, {
  weights = {
    accuracy = 1.0,
    latency = -0.001
  }
})

optimizer.num_trials = 20

local best_program, metrics = optimizer:Compile(trainset, valset)

print("Best accuracy:", metrics.accuracy)
print("Avg latency:", metrics.avg_latency_ms, "ms")
```

### ACE Self-Improving Agent

```lua
local ACE = require("dslua.agents.ace")

local agent = ACE.new(module, {
  rules = {
    {
      key = "calculate",
      action = "CALCULATE",
      condition = function(state)
        return state.task.question:match("calc") ~= nil
      end,
      threshold = 0.6
    }
  }
})

-- Learn from execution
local trace = agent:Execute(task, ctx)

local result = agent:LearnFromExecution(trace, {
  learning_rate = 0.1,
  credit_method = "td"
})

-- Weights updated automatically
```

---

## 📦 Installation

```bash
git clone https://github.com/postfix/dslua.git
cd dslua
luarocks --only-deps install --lua-version=5.1
busted  # Run tests
```

**Dependencies:**
- LuaJIT 2.1+
- lua-cjson (for JSON handling)
- lua-http (for LLM providers)
- busted (testing framework)

---

## 🧪 Testing

```bash
# Run all tests
busted

# Run specific test suite
busted specs/optimizers/
busted specs/agents/

# Verbose output
busted --verbose
```

**Test Coverage:** 1022 tests passing (0 failures, 0 errors, 5 API-key dependent)

---

## 📖 Documentation

### Core Modules

- **[Core Abstractions](docs/core/README.md)** - Signature, Field, Context
- **[Modules Guide](docs/modules/README.md)** - Predict, ChainOfThought, ReAct, etc.
- **[LLM Providers](docs/llms/README.md)** - Anthropic, OpenAI, Gemini, Ollama

### Optimizers

- **[BootstrapFewShot](docs/optimizers/bootstrap_fewshot.md)** - Random subset optimization
- **[MIPRO Design](docs/plans/2026-02-02-mipro-optimizer-design.md)** - Complete MIPRO architecture

### Agents

- **[ACE Framework](docs/plans/2026-02-02-ace-phase3-pattern-mining.md)** - Self-improving agents
  - Phase 1: Decision Engine
  - Phase 2: Learning from Demonstrations
  - Phase 3: Pattern Mining & Outcome Feedback

### Examples

- **[MIPRO Usage](examples/mipro_optimizer_example.lua)** - Optimizer examples
- **[MIPRO + ACE Integration](examples/mipro_ace_integration_example.lua)** - Combined usage
- **[Parallel Processing](examples/parallel_processing_example.lua)** - Concurrent batch processing
- **[Tool Chaining](examples/tool_chaining_example.lua)** - Tool composition and pipelines
- **[A2A Protocol](examples/a2a_protocol_example.lua)** - Multi-agent coordination
- **[Performance Benchmarking](examples/benchmarking_example.lua)** - Performance measurement and analysis
- **[RAG Retrieval](examples/retrieve_rag_example.lua)** - Retrieval-augmented generation
- **[RLM Retriever](examples/rlm_retriever_example.lua)** - Multi-pass context exploration ✨ NEW
- **[SIMBA Optimizer](examples/simba_optimizer_example.lua)** - Similarity-based bootstrap
- **[GEPA Optimizer](examples/gepa_optimizer_example.lua)** - Ensemble prompt augmentation
- **[COPRO Optimizer](examples/copro_optimizer_example.lua)** - Coordinate descent optimization ✨ NEW

---

## 🎓 Usage Patterns

### 1. Simple Prompt Optimization

```lua
local MIPRO = require("dslua.optimizers.mipro")

local optimizer = MIPRO.new(base_program)
optimizer.num_trials = 10

local best = optimizer:Compile(trainset, valset)
```

### 2. Multi-Objective Optimization

```lua
local optimizer = MIPRO.new(program, {
  weights = {
    accuracy = 1.0,
    latency = -0.001,
    cost = -0.0001
  }
})
```

### 3. Agent Learning from Execution

```lua
local trace = agent:Execute(task, ctx)
local result = agent:LearnFromExecution(trace, {
  credit_method = "td"
})
```

### 4. Threshold Adaptation

```lua
local recent = {
  {matched = true, success = false},
  {matched = true, success = true}
}

local new_threshold = agent:AdaptThresholdOnline("rule_name", recent, {
  target_metric = "precision",
  target = 0.8
})
```

---

## 🏗️ Architecture

### Module Hierarchy

```
dslua/
├── core/           # Core abstractions (Signature, Field, Context)
├── modules/        # Program modules (Predict, ChainOfThought, etc.)
├── agents/         # Agent frameworks (ACE, ReActAgent)
├── optimizers/     # Program optimizers (MIPRO, BootstrapFewShot)
├── llms/           # LLM providers (Anthropic, OpenAI, etc.)
└── tools/          # Tool registry and built-in tools
```

### Design Principles

1. **Declarative** - Declare what, not how
2. **Composable** - Combine modules like building blocks
3. **Optimizable** - Automatic prompt optimization
4. **Observable** - Trace execution for debugging
5. **Efficient** - LuaJIT performance with minimal overhead

---

## 📊 Feature Parity with DSPy-Go

**Overall: 100% parity** 🎉

| Component | Parity | Notes |
|-----------|--------|-------|
| Core Modules | 100% | 9/9 modules complete (Predict, CoT, ReAct, Refine, FewShot, Structured, Parallel, Retrieve, RLM) |
| LLM Providers | 100% | 5/5 major providers (Anthropic, OpenAI, Gemini, Ollama, LlamaCPP) ✅ |
| Agents | 100% | ACE (Phases 1-3), ReActAgent, A2A Protocol ✅ |
| Optimizers | 100% | MIPRO + BootstrapFewShot + SIMBA + GEPA + COPRO ✅ |
| Structured Output | 100% | JSON + XML schema with validation ✅ |
| Tools | 100% | Registry + built-ins + chaining/composition + Bayesian selection + MCP ✅ |
| Evaluation | 100% | Metrics + Session Logger ✅ |
| CLI | 100% | Try command + REPL ✅ |

See [Feature Parity Review](docs/plans/2026-02-02-feature-parity-review.md) for details.

---

## 🚧 Roadmap

### ✅ Completed (v1.0)

- [x] Core modules (Predict, CoT, ReAct, Refine, FewShot)
- [x] LLM providers (Anthropic, OpenAI, Gemini, Ollama, LlamaCPP) ✅
- [x] Structured output with JSON schema
- [x] BootstrapFewShot optimizer
- [x] **MIPRO optimizer** with TPE
- [x] **ACE agent** (Phases 1-3)
  - [x] Rule-based decision engine
  - [x] Learning from demonstrations
  - [x] Temporal credit assignment
  - [x] Threshold learning & adaptation
- [x] **Parallel module** for concurrent batch processing
- [x] **Tool chaining and composition** (Chain, Parallel, Condition, Loop, Composite)
- [x] **Bayesian tool selection** with Thompson Sampling ✅
- [x] **A2A protocol** for multi-agent coordination
- [x] **Performance benchmarking suite** (Benchmark, Comparison, Suite, Profiler, MemoryMonitor)
- [x] **Retrieve module** for RAG with VectorRetriever, BM25Retriever, and HybridRetriever
- [x] **RLM (Retrieve Language Model)** for multi-pass context exploration with query expansion
- [x] **SIMBA optimizer** for similarity-based bootstrap optimization
- [x] **GEPA optimizer** for ensemble prompt augmentation
- [x] **COPRO optimizer** for coordinate descent optimization
- [x] **Evaluation/Metrics module** with accuracy, ROUGE, BLEU, latency, cost ✅
- [x] **CLI try command** for instant optimizer testing ✅
- [x] **MCP Integration** for Model Context Protocol ✅
- [x] **XML Adapter** for structured XML output ✅
- [x] **Session Logger** for execution trace analysis ✅
- [x] **Interactive REPL** for exploration ✅

### 🔄 In Progress

- [ ] Advanced teleprompting

### 📋 Planned

- [ ] Enhanced tool composition
- [ ] Multi-agent orchestration
- [ ] Distributed training
- [ ] Production deployment guides

---

## 💡 Contributing

Contributions welcome! Areas of interest:

1. **Advanced Optimizers** - SIMBA, GEPA, COPRO implementations
2. **Tool Composition** - Chaining and composite tools
4. **Multi-Agent** - A2A protocol for agent coordination
5. **Performance** - Benchmarking and optimization

See [Contributing Guide](CONTRIBUTING.md) for details.

---

## 📄 License

MIT License - see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- **Stanford NLP** - Original [DSPy](https://github.com/stanfordnlp/dspy) framework
- **XiaoConstantine** - [DSPy-Go](https://github.com/XiaoConstantine/dspy-go) reference implementation
- **LuaJIT team** - High-performance Lua compiler

---

**Built with ❤️ for the LuaJIT ecosystem**
