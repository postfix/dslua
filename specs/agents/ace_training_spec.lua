-- specs/agents/ace_training_spec.lua
describe("ACE Training - LoadDemos", function()
  local LoadDemos, ValidateDemoStructure

  setup(function()
    local training = require("dslua.agents.ace_training")
    LoadDemos = training.LoadDemos
    ValidateDemoStructure = training.ValidateDemoStructure
  end)

  it("validates demo structure correctly", function()
    local demo = {
      demo_id = "test_001",
      trace = {
        {
          step = 0,
          demonstrated_action = "REASON",
          state_snapshot = {
            task = {task_type = "math"},
            self = {confidence = 0.5, steps_taken = 0}
          }
        }
      },
      outcome = {success = true, termination_reason = "SUCCESS", steps_taken = 1}
    }

    local validation = ValidateDemoStructure(demo)

    assert.is_true(validation.valid)
    assert.is_equal(0, #validation.errors)
  end)

  it("detects missing demo_id", function()
    local demo = {
      trace = {},
      outcome = {success = true}
    }

    local validation = ValidateDemoStructure(demo)

    assert.is_false(validation.valid)
    assert.is_true(#validation.errors > 0)
  end)

  it("detects invalid action", function()
    local demo = {
      demo_id = "test_002",
      trace = {
        {
          step = 0,
          demonstrated_action = "INVALID_ACTION",
          state_snapshot = {
            task = {},
            self = {}
          }
        }
      },
      outcome = {success = true}
    }

    local validation = ValidateDemoStructure(demo)

    assert.is_false(validation.valid)
    assert.is_true(#validation.errors > 0)
  end)

  it("detects missing task layer", function()
    local demo = {
      demo_id = "test_003",
      trace = {
        {
          step = 0,
          demonstrated_action = "REASON",
          state_snapshot = {
            self = {confidence = 0.5}  -- Missing task layer
          }
        }
      },
      outcome = {success = true}
    }

    local validation = ValidateDemoStructure(demo)

    assert.is_false(validation.valid)
    assert.is_true(#validation.errors > 0)
  end)
end)

describe("ACE Training - TrainFromDemos", function()
  local M

  setup(function()
    M = require("dslua.agents.ace_training")
  end)

  it("trains for multiple epochs with early stopping", function()
    local rules = {
      {
        id = 1,
        key = "rule1",
        conditions = {{feature = "task_type", op = "==", value = "math"}},
        action = "RETRIEVE",
        default_weight = 0.5
      }
    }

    local demos = {
      train = {
        {
          demo_id = "train_001",
          valid = true,
          trace = {{
            step = 0,
            demonstrated_action = "RETRIEVE",
            state_snapshot = {task = {task_type = "math"}, self = {confidence = 0.5}}
          }},
          outcome = {success = true}
        }
      },
      val = {
        {
          demo_id = "val_001",
          valid = true,
          trace = {{
            step = 0,
            demonstrated_action = "RETRIEVE",
            state_snapshot = {task = {task_type = "math"}, self = {confidence = 0.5}}
          }},
          outcome = {success = true}
        }
      }
    }

    local opts = {
      epochs = 3,
      learning_rate = 0.05,
      max_weight_delta = 0.02,
      min_margin = 0.05,
      epsilon = 0.01,
      early_stopping_patience = 2,
      seed = 42
    }

    local result = M.TrainFromDemos(demos, rules, opts)

    assert.is_not_nil(result.trained_weights)
    assert.is_true(#result.metrics_history > 0)
    assert.is_true(result.best_epoch >= 1 and result.best_epoch <= opts.epochs)
  end)
end)
