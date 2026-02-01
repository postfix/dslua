-- dslua/agents/ace_training.lua
local json = require("dkjson")
local M = {}

function M.ValidateDemoStructure(demo)
  local errors = {}
  local valid_actions = {
    "REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"
  }

  -- Check required fields
  if not demo.demo_id then
    table.insert(errors, "Missing demo_id")
  end

  if not demo.trace or type(demo.trace) ~= "table" then
    table.insert(errors, "Missing or invalid trace")
  else
    -- Validate each step
    for step_idx, step in ipairs(demo.trace) do
      -- Check demonstrated_action
      local valid_action = false
      for _, action in ipairs(valid_actions) do
        if step.demonstrated_action == action then
          valid_action = true
          break
        end
      end
      if not valid_action then
        table.insert(errors, string.format("Invalid action at step %d", step.step or step_idx))
      end

      -- Check state_snapshot
      if not step.state_snapshot then
        table.insert(errors, string.format("Missing state_snapshot at step %d", step.step or step_idx))
      else
        local snap = step.state_snapshot
        if not snap.task then
          table.insert(errors, string.format("Missing task layer at step %d", step.step or step_idx))
        end
        if not snap.self then
          table.insert(errors, string.format("Missing self layer at step %d", step.step or step_idx))
        end
      end
    end
  end

  if not demo.outcome then
    table.insert(errors, "Missing outcome")
  end

  return {
    valid = #errors == 0,
    errors = errors
  }
end

function M.LoadDemos(directory, opts)
  opts = opts or {}
  local split_ratio = opts.split_ratio or 0.8
  local validate = opts.validate ~= false  -- Default: true
  local shuffle = opts.shuffle ~= false     -- Default: true

  local demos = {}

  -- Scan directory for JSON files
  local handle = io.popen("find '" .. directory .. "' -maxdepth 1 -name '*.json' -type f")
  if not handle then
    return nil, "Failed to scan directory"
  end

  for filename in handle:lines() do
    local f = io.open(filename, "r")
    if f then
      local content = f:read("*all")
      f:close()

      local demo, _, err = json.decode(content, 1, nil)
      if demo then
        demo.valid = true
        demo.filepath = filename

        if validate then
          local validation = M.ValidateDemoStructure(demo)
          demo.valid = validation.valid
          demo.errors = validation.errors
        end

        table.insert(demos, demo)
      end
    end
  end
  handle:close()

  -- Shuffle if requested
  if shuffle then
    local seed = opts.seed or os.time()
    math.randomseed(seed)
    for i = #demos, 2, -1 do
      local j = math.random(i)
      demos[i], demos[j] = demos[j], demos[i]
    end
  end

  -- Split into train/val
  local split_idx = math.floor(#demos * split_ratio)
  local train = {}
  local val = {}

  for i, demo in ipairs(demos) do
    if i <= split_idx then
      table.insert(train, demo)
    else
      table.insert(val, demo)
    end
  end

  return {
    train = train,
    val = val
  }
end

function M.TrainFromDemos(demos, rules, opts)
  opts = opts or {}

  -- Set defaults
  local epochs = opts.epochs or 10
  local learning_rate = opts.learning_rate or 0.05
  local max_weight_delta = opts.max_weight_delta or 0.02
  local min_margin = opts.min_margin or 0.05
  local epsilon = opts.epsilon or 0.01
  local patience = opts.early_stopping_patience or 3
  local seed = opts.seed or os.time()

  -- Initialize weights
  local weights = {}
  for _, rule in ipairs(rules) do
    weights[rule.key] = rule.default_weight
  end

  -- Best tracking
  local best_val_loss = math.huge
  local best_weights = {}
  local best_epoch = 1
  local patience_counter = 0

  local metrics_history = {}

  -- Training loop
  for epoch = 1, epochs do
    local epoch_metrics = {
      epoch = epoch,
      train_loss = 0,
      train_updates = 0,
      train_coverage_failures = 0,
      val_loss = 0,
      val_updates = 0,
      val_coverage_failures = 0
    }

    -- Train on training set
    for _, demo in ipairs(demos.train) do
      if not demo.valid then
        goto continue_train
      end

      for _, step in ipairs(demo.trace) do
        local decision = {
          demonstrated_action = step.demonstrated_action,
          state_snapshot = step.state_snapshot
        }

        local step_opts = {
          learning_rate = learning_rate,
          max_weight_delta = max_weight_delta,
          min_margin = min_margin,
          epsilon = epsilon,
          salience_mode = "binary"
        }

        local learning = require("dslua.agents.ace_learning")
        local NormalizeState = require("dslua.agents.ace_decision").NormalizeState
        local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}

        local metrics = learning.LearnFromDemonstration(
          decision, rules, weights, step_opts, NormalizeState, ACTIONS_ORDER
        )

        if metrics.updated then
          epoch_metrics.train_loss = epoch_metrics.train_loss - metrics.margin
          epoch_metrics.train_updates = epoch_metrics.train_updates + 1
        else
          if metrics.uncovered then
            epoch_metrics.train_coverage_failures = epoch_metrics.train_coverage_failures + 1
          end
        end
      end

      ::continue_train::
    end

    -- Validate on validation set
    for _, demo in ipairs(demos.val) do
      if not demo.valid then
        goto continue_val
      end

      for _, step in ipairs(demo.trace) do
        local decision = {
          demonstrated_action = step.demonstrated_action,
          state_snapshot = step.state_snapshot
        }

        local Decision = require("dslua.agents.ace_decision")
        local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}
        local scores = Decision.ScoreActions(
          decision.state_snapshot, rules, weights, ACTIONS_ORDER
        )

        local score_star = scores[decision.demonstrated_action] or 0

        -- Find best competitor
        local best_comp = 0
        for _, action in ipairs(ACTIONS_ORDER) do
          if action ~= decision.demonstrated_action then
            local s = scores[action] or 0
            if s > best_comp then
              best_comp = s
            end
          end
        end

        local margin = score_star - best_comp
        epoch_metrics.val_loss = epoch_metrics.val_loss - margin

        if margin < min_margin then
          epoch_metrics.val_updates = epoch_metrics.val_updates + 1
        end
      end

      ::continue_val::
    end

    table.insert(metrics_history, epoch_metrics)

    -- Early stopping check
    if epoch_metrics.val_loss < best_val_loss then
      best_val_loss = epoch_metrics.val_loss
      best_epoch = epoch
      -- Copy best weights
      for k, v in pairs(weights) do
        best_weights[k] = v
      end
      patience_counter = 0
    else
      patience_counter = patience_counter + 1
      if patience_counter >= patience then
        break  -- Early stopping
      end
    end
  end

  -- Restore best weights
  for k, v in pairs(best_weights) do
    weights[k] = v
  end

  return {
    trained_weights = weights,
    metrics_history = metrics_history,
    best_epoch = best_epoch
  }
end

return M
