-- dslua/cli/try.lua
-- CLI Testing Interface for instant optimizer testing

local M = {}

-- =============================================================================
-- Try Command - Test optimizers instantly
-- =============================================================================

M.TryCommand = {}
M.TryCommand.__index = M.TryCommand

function M.TryCommand.new(opts)
  opts = opts or {}

  local self = {
    -- Available datasets
    datasets = opts.datasets or {},

    -- Available optimizers
    optimizers = opts.optimizers or {},

    -- Default configuration
    default_config = opts.default_config or {}
  }

  setmetatable(self, M.TryCommand)
  return self
end

-- Register a dataset
function M.TryCommand:register_dataset(name, dataset)
  self.datasets[name] = dataset
end

-- Register an optimizer
function M.TryCommand:register_optimizer(name, optimizer_class)
  self.optimizers[name] = optimizer_class
end

-- Parse and execute try command
function M.TryCommand:execute(args)
  -- Usage: try optimizer --dataset <name> --trials <N> --config <key=value>

  local parser = self:_create_parser()
  local options = parser:parse(args)

  -- Validate options
  if not options.optimizer then
    return nil, "Optimizer name required"
  end

  if not options.dataset and not options.trainset then
    return nil, "Dataset or trainset required"
  end

  -- Get dataset
  local trainset, valset
  if options.dataset then
    local dataset = self.datasets[options.dataset]
    if not dataset then
      return nil, "Dataset not found: " .. options.dataset
    end
    trainset = dataset.trainset or dataset
    valset = dataset.valset or {}
  else
    trainset = options.trainset
    valset = options.valset or {}
  end

  -- Get optimizer
  local optimizer_class = self.optimizers[options.optimizer]
  if not optimizer_class then
    return nil, "Optimizer not found: " .. options.optimizer
  end

  -- Create base program
  local base_program = options.program
  if not base_program then
    return nil, "Base program required"
  end

  -- Merge config
  local config = self:_merge_config(self.default_config, options.config)

  -- Create optimizer
  local optimizer = optimizer_class.new(base_program, {
    trainset = trainset,
    valset = valset,
    num_trials = options.trials or config.num_trials or 10
  })

  -- Run optimization
  local ctx = options.context or require("dslua.core.context").new({})
  local best_program, metrics = optimizer:Compile(ctx)

  -- Format results
  local results = {
    optimizer = options.optimizer,
    dataset = options.dataset,
    trials = options.trials or config.num_trials or 10,
    best_score = metrics.score or metrics.accuracy or 0,
    metrics = metrics,
    program = best_program
  }

  return results
end

-- Create argument parser
function M.TryCommand:_create_parser()
  local parser = {
    args = {}
  }

  function parser:parse(args)
    local options = {
      optimizer = nil,
      dataset = nil,
      trainset = nil,
      valset = nil,
      trials = nil,
      config = {},
      program = nil,
      context = nil
    }

    local i = 1
    while i <= #args do
      local arg = args[i]

      if arg == "--optimizer" or arg == "-o" then
        options.optimizer = args[i + 1]
        i = i + 2
      elseif arg == "--dataset" or arg == "-d" then
        options.dataset = args[i + 1]
        i = i + 2
      elseif arg == "--trials" or arg == "-t" then
        options.trials = tonumber(args[i + 1])
        i = i + 2
      elseif arg == "--config" or arg == "-c" then
        local config_str = args[i + 1]
        local key, value = config_str:match("^([^=]+)=(.+)$")
        if key and value then
          -- Try to parse as number
          local num_value = tonumber(value)
          if num_value then
            options.config[key] = num_value
          elseif value == "true" then
            options.config[key] = true
          elseif value == "false" then
            options.config[key] = false
          else
            options.config[key] = value
          end
        end
        i = i + 2
      elseif arg == "--program" or arg == "-p" then
        options.program = args[i + 1]
        i = i + 2
      else
        i = i + 1
      end
    end

    return options
  end

  return parser
end

-- Merge configurations
function M.TryCommand:_merge_config(default, override)
  local merged = {}

  for k, v in pairs(default) do
    merged[k] = v
  end

  if override then
    for k, v in pairs(override) do
      merged[k] = v
    end
  end

  return merged
end

-- Format results for display
function M.TryCommand:format_results(results)
  local lines = {}

  table.insert(lines, "=== Optimization Results ===")
  table.insert(lines, string.format("Optimizer: %s", results.optimizer or "unknown"))
  table.insert(lines, string.format("Dataset: %s", results.dataset or "custom"))
  table.insert(lines, string.format("Trials: %d", results.trials))
  table.insert(lines, "")

  table.insert(lines, "Best Score:")
  table.insert(lines, string.format("  %.4f", results.best_score))
  table.insert(lines, "")

  if results.metrics then
    table.insert(lines, "Metrics:")
    for key, value in pairs(results.metrics) do
      if type(value) == "number" then
        table.insert(lines, string.format("  %s: %.4f", key, value))
      elseif type(value) ~= "table" then
        table.insert(lines, string.format("  %s: %s", key, tostring(value)))
      end
    end
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

-- List available optimizers
function M.TryCommand:list_optimizers()
  local lines = {}

  table.insert(lines, "Available Optimizers:")
  for name, _ in pairs(self.optimizers) do
    table.insert(lines, string.format("  - %s", name))
  end

  return table.concat(lines, "\n")
end

-- List available datasets
function M.TryCommand:list_datasets()
  local lines = {}

  table.insert(lines, "Available Datasets:")
  for name, dataset in pairs(self.datasets) do
    local size = dataset.trainset and #dataset.trainset or #dataset
    table.insert(lines, string.format("  - %s (%d examples)", name, size))
  end

  return table.concat(lines, "\n")
end

-- =============================================================================
-- Built-in Datasets
-- =============================================================================

M.BuiltinDatasets = {
  -- GSM8K-style math problems
  gsm8k = {
    trainset = {
      {question = "What is 2 + 2?", answer = "4"},
      {question = "What is 3 * 3?", answer = "9"},
      {question = "What is 10 / 2?", answer = "5"},
      {question = "What is 5 + 7?", answer = "12"},
      {question = "What is 8 - 3?", answer = "5"}
    }
  },

  -- Sentiment analysis
  sentiment = {
    trainset = {
      {text = "I love this product", sentiment = "positive"},
      {text = "This is terrible", sentiment = "negative"},
      {text = "It's okay", sentiment = "neutral"},
      {text = "Amazing experience", sentiment = "positive"},
      {text = "Very disappointed", sentiment = "negative"}
    }
  },

  -- Question answering
  qa = {
    trainset = {
      {context = "Paris is the capital of France", question = "What is the capital of France?", answer = "Paris"},
      {context = "Python is a programming language", question = "What is Python?", answer = "A programming language"},
      {context = "The sky is blue", question = "What color is the sky?", answer = "blue"}
    }
  }
}

-- =============================================================================
-- Built-in Optimizers
-- =============================================================================

M.BuiltinOptimizers = {
  BootstrapFewShot = "BootstrapFewShot",
  MIPRO = "MIPRO",
  SIMBA = "SIMBA",
  GEPA = "GEPA",
  COPRO = "COPRO"
}

-- =============================================================================
-- Helper Functions
-- =============================================================================

function M.create_try_command(opts)
  return M.TryCommand.new(opts)
end

-- Quick test function
function M.try(optimizer_name, program, trainset, opts)
  opts = opts or {}

  local Context = require("dslua.core.context")

  -- Get optimizer class
  local optimizer_class
  if type(optimizer_name) == "string" then
    optimizer_class = require("dslua.optimizers." .. optimizer_name:lower())
  else
    optimizer_class = optimizer_name
  end

  -- Create optimizer
  local optimizer = optimizer_class.new(program, {
    trainset = trainset,
    valset = opts.valset or {},
    num_trials = opts.trials or 5
  })

  -- Compile
  local ctx = opts.context or Context.new({})
  local best_program, metrics = optimizer:Compile(ctx, opts.trials or 5)

  return best_program, metrics
end

return M
