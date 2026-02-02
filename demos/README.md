# ACE Training Demos

This directory contains demonstration traces for training ACE agents.

## Directory Structure

```
demos/
├── examples/          # Example demo files for testing
├── training/          # Full training dataset
└── validation/        # Validation dataset (optional)
```

## Demo Format

Demos use the **ACE Trace Format**, capturing full execution state:

```json
{
  "demo_id": "unique_identifier",
  "metadata": {
    "task_difficulty": "easy|medium|hard",
    "teacher_confidence": 0.0-1.0,
    "tags": ["tag1", "tag2"]
  },
  "trace": [
    {
      "step": 0,
      "demonstrated_action": "REASON|RETRIEVE|DECOMPOSE|SYNTHESIZE|VERIFY|TERMINATE",
      "state_snapshot": {
        "task": {
          "task_type": "math|factual|code|general",
          "complexity_estimate": 0.0-1.0,
          "input_length": 0.0-1.0,
          "entity_count": 0.0-1.0,
          "tool_requirements": ["tool1", "tool2"]
        },
        "self": {
          "confidence": 0.0-1.0,
          "steps_taken": 0,
          "prev_action": null|"ACTION"
        },
        "history": {
          "total_executions": 0,
          "success_rate": {}
        }
      }
    }
  ],
  "outcome": {
    "success": true|false,
    "termination_reason": "SUCCESS|TIMEOUT|ERROR",
    "steps_taken": 1
  }
}
```

## Usage

### Train from Demo Directory

```lua
local ACE = require("dslua.agents.ace")
local rules = require("dslua.agents.ace_rules")

local agent = ACE.new(module, {rules = rules})

local result = agent:TrainFromDemoDirectory("demos/training", {
  epochs = 10,
  learning_rate = 0.05,
  max_weight_delta = 0.02,
  early_stopping_patience = 3,
  split_ratio = 0.8,
  shuffle = true,
  seed = 42
})

print(string.format("Training complete. Best epoch: %d", result.best_epoch))

-- Export learned weights
agent:ExportLearnedWeights("weights/learned.json")
```

### Load Learned Weights

```lua
local agent = ACE.new(module, {rules = rules})

agent:LoadWeightOverrides("weights/learned.json")

-- Agent now uses learned weights for decision-making
```

## Demo Collection Guidelines

1. **Diverse Coverage**: Include various task types (math, factual, code, general)
2. **Edge Cases**: Include difficult cases that require specific actions
3. **State Completeness**: Ensure all state layers (task/self/history) are populated
4. **Action Validation**: Only use valid actions from the 6 ACE actions
5. **Metadata**: Tag demos with difficulty, confidence, and domain tags

## Training Tips

- **Start Small**: Begin with 10-20 demos to test the pipeline
- **Validate First**: Use `validate = true` to catch schema errors
- **Monitor Metrics**: Check `metrics_history` for loss convergence
- **Early Stopping**: Use patience=3-5 to prevent overfitting
- **Reproducibility**: Set `seed` for consistent train/val splits

## Troubleshooting

**Coverage Failures**: Demo action has no supporting rules → Add rules or filter demos

**High Validation Loss**: Model overfitting → Increase early_stopping_patience or reduce epochs

**No Weight Changes**: All demos have sufficient margin → Decrease min_margin

**Clamping Events**: max_weight_delta too small → Increase or reduce learning_rate
