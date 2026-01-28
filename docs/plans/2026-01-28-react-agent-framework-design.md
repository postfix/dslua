# ReAct Agent Framework Design

**Date:** 2026-01-28
**Phase:** Phase 3 - Agents and Advanced Features
**Status:** Design Approved

## Overview

The ReAct Agent Framework provides a sophisticated, production-ready agent system that combines ReAct reasoning with tool orchestration. It manages multi-step conversations, maintains enhanced context with running summaries, handles errors with retry logic, and presents results in configurable formats.

## Architecture

### Layered System Design

The framework is built as a layered system on top of existing dslua modules:

1. **Tool Registry Layer** - Centralized tool discovery and registration
2. **Agent Base Class** - Common agent functionality and workflow orchestration
3. **ReActAgent** - ReAct reasoning with enhanced capabilities
4. **Built-in Tools** - Practical utilities + examples for custom tools

This layered approach maintains clear separation of concerns while enabling extensibility. Other agent types (like ACEAgent) can be added by extending the same base class.

### Key Architectural Decisions

- **Agent base class pattern** - Allows multiple agent types with shared functionality
- **Tool Registry module** - Centralized organization with clear discovery API
- **Enhanced context** - Track individual steps plus running conversation summary
- **Hybrid termination** - Agent-controlled "finish" action with max iteration safety net
- **Retry with backoff** - Resilient tool execution with exponential backoff
- **Configurable output** - Simple string or structured result object

## Components

### 1. Tool Registry (`dslua/tools/registry.lua`)

**Purpose:** Centralized tool registration, discovery, and retrieval

**API:**
```lua
registry:Register(name, tool, metadata)  -- Register a tool
registry:Get(name)                       -- Retrieve tool by name
registry:List(category)                  -- List all tools in category
registry:Has(name)                       -- Check if tool exists
```

**Built-in Tools (Hybrid Approach):**
- **Calculator**: Arithmetic operations (add, subtract, multiply, divide)
- **StringHelper**: String manipulation (length, uppercase, lowercase, trim)
- **SearchTool**: Simple search interface (stub or connected to search API)

**Metadata Structure:**
```lua
{
    description = "Tool description",
    category = "basic|utility|user",
    parameters = {"param1", "param2"},
    examples = {"Example usage"}
}
```

### 2. Agent Base Class (`dslua/agents/base.lua`)

**Purpose:** Shared agent functionality for all agent types

**Responsibilities:**
- Execution loop management with max_iterations safety
- Result formatting (simple vs structured)
- Template methods for subclass customization
- Error handling patterns

**Template Methods:**
```lua
:_initialize(state, input)     -- Setup initial state
:_shouldStop(state)             -- Check termination condition
:_executeStep(ctx, state)       -- Execute single reasoning step
:_updateSummary(state, step)    -- Update conversation summary
:_formatResult(state, mode)     -- Format final output
```

**Configuration Options:**
```lua
{
    max_iterations = 10,         -- Safety limit
    output_mode = "simple|structured",
    retry_config = {...}         -- Retry settings
}
```

### 3. ReActAgent (`dslua/agents/react_agent.lua`)

**Purpose:** ReAct reasoning with enhanced capabilities

**Initialization:**
```lua
local agent = ReActAgent.new(signature, {
    tool_registry = registry,
    max_iterations = 10,
    output_mode = "structured",
    retry_config = {
        max_retries = 3,
        initial_delay = 100,
        backoff_multiplier = 2.0
    }
})
```

**State Object:**
```lua
{
    steps = {},              -- Individual reasoning steps
    summary = "",            -- Running conversation summary
    current_iteration = 1,   -- Current step number
    tool_usage = {},         -- Tool call counts
    errors = {}              -- Error history
}
```

**Execution Flow:**
1. Initialize enhanced state with conversation summary tracking
2. Load tools from registry
3. For each iteration:
   - Build ReAct prompt with current context and summary
   - Execute ReAct reasoning step
   - Track tool usage (increment call counts)
   - Handle errors with retry logic
   - Update conversation summary
   - Check termination (finish action or max_iterations)
4. Format and return result

### 4. Enhanced Context Management

**Running Summary:**
- Updated after each iteration via LLM call
- Includes: current objective, actions taken, key observations, current state
- Configurable update frequency (every step vs. every N steps)
- Included in subsequent ReAct prompts as "Conversation so far:"

**Step Tracking:**
Each step records:
```lua
{
    iteration = 1,
    thought = "I need to calculate",
    action = "calculator",
    args = "2+2",
    observation = "4",
    timestamp = "2026-01-28T12:00:00Z"
}
```

### 5. Error Handling and Retry Logic

**Retry Configuration:**
```lua
{
    max_retries = 3,              -- Maximum retry attempts
    initial_delay = 100,          -- Starting delay (ms)
    backoff_multiplier = 2.0,     -- Delay multiplier
    retryable_errors = {          -- Error patterns to retry
        "timeout",
        "connection refused"
    }
}
```

**Retry Flow:**
1. Wrap tool execution in pcall
2. On failure: check if error is retryable
3. If retryable: wait `delay * (backoff_multiplier ^ attempt)` ms
4. Retry up to max_retries
5. If exhausted: format error as observation, continue loop
6. Track all errors in state.error_history

**Error Tracking:**
```lua
{
    tool = "calculator",
    error = "Division by zero",
    retries = 3,
    recovered = false,
    timestamp = "2026-01-28T12:00:00Z"
}
```

### 6. Result Presentation

**Simple Mode:**
```lua
local agent = ReActAgent.new(signature, {output_mode = "simple"})
local result = agent:Execute(ctx, input)
-- Returns: "42"
```

**Structured Mode:**
```lua
local agent = ReActAgent.new(signature, {output_mode = "structured"})
local result = agent:Execute(ctx, input)
-- Returns:
{
    answer = "42",
    reasoning = {...},
    tool_usage = {calculator = 2, search = 1},
    iterations = 5,
    summary = "Conversation summary",
    error_history = {...},
    trace = {...}
}
```

## Data Flow

```
User Input
    ↓
Agent:Execute(ctx, input, opts)
    ↓
Initialize State (steps=[], summary="", iteration=1)
    ↓
Loop (until finish or max_iterations):
    ↓
    Build ReAct Prompt (with context + summary)
    ↓
    ReAct:Process(ctx, prompt) → thought, action, args
    ↓
    Execute Tool (with retry logic)
    ↓
    Track Tool Usage (increment counts)
    ↓
    Update Summary (LLM call to condense conversation)
    ↓
    Check Termination (finish action?)
    ↓
Format Result (simple or structured)
    ↓
Return Result
```

## File Structure

```
dslua/
├── agents/
│   ├── base.lua              # Agent base class
│   ├── react_agent.lua       # ReAct agent implementation
│   └── init.lua              # Package exports
├── tools/
│   ├── registry.lua           # Tool registry
│   ├── builtin/
│   │   ├── calculator.lua     # Calculator tool
│   │   ├── string_helper.lua # String manipulation
│   │   └── search.lua         # Search tool
│   └── init.lua              # Export Tool, Registry
```

## Testing Strategy

### Unit Tests
- Tool Registry: Registration, retrieval, listing, duplicates
- Agent Base Class: Iteration limits, result formatting, state management
- ReActAgent: Initialization, tool loading, context management
- Built-in Tools: Calculator, StringHelper functionality

### Integration Tests
- ReActAgent with mock LLM: Reasoning loop, tool calling, termination
- ReActAgent with real tools: Tool execution, error recovery
- Retry Logic: Failure simulation, backoff verification
- Enhanced Context: Summary generation, context propagation

### End-to-End Tests
- Complete execution with Ollama (local testing)
- Multi-step scenarios with multiple tool calls
- Error recovery scenarios
- Long conversations (10+ steps)

## Implementation Considerations

### Lua Idioms
- Use metatables for OOP (agent and tool inheritance)
- Table-based state management
- String patterns for error matching
- os.time() for timestamps

### Performance
- Summary updates: Configurable frequency (default every step)
- Tool caching: Registry caches tool lookups
- Retry delays: Configurable to avoid excessive waiting in tests

### Extensibility
- Agent base class enables other agent types (ACEAgent, etc.)
- Tool registry supports user-defined tools
- Output mode can be extended (e.g., "json", "verbose")

## Success Criteria

- [ ] Tool Registry functional with built-in tools
- [ ] Agent base class with execution loop
- [ ] ReActAgent with enhanced context
- [ ] Retry logic with exponential backoff
- [ ] Configurable output (simple/structured)
- [ ] All tests passing (50+ new tests)
- [ ] End-to-end scenarios working with Ollama
- [ ] Documentation and examples updated

## Next Steps

1. Create implementation plan (writing-plans skill)
2. Set up isolated git worktree (using-git-worktrees skill)
3. Implement following TDD workflow
4. Verify with end-to-end tests
5. Update documentation (DESIGN.md, README.md)
