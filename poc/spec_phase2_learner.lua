-- poc/spec_phase2_learner.lua
describe("Phase2Learner - LearnFromDecision", function()
    local Phase2Learner, Phase1Adapter, RULES

    setup(function()
        Phase2Learner = require("poc.ace_phase2_poc")
        Phase1Adapter = require("poc.phase1_adapter")
        RULES = require("poc.rules_poc")
    end)

    local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}

    it("should error on invalid demonstrated_action", function()
        local adapter = Phase1Adapter.new()
        local learner = Phase2Learner.new(adapter)
        local weights = {}
        local opts = {learning_rate = 0.05, max_weight_delta = 0.02, min_margin = 0.05, epsilon = 0.01}

        local decision = {
            demonstrated_action = "INVALID_ACTION",
            state_snapshot = {
                task = {task_type = "math", complexity_estimate = 0.2},
                self = {confidence = 0.5, steps_taken = 0}
            }
        }

        assert.has_error(function()
            learner:LearnFromDecision(decision, RULES, weights, opts)
        end, "Invalid demonstrated_action")
    end)

    it("should compute scores correctly for Demo 1 (no competitor)", function()
        local adapter = Phase1Adapter.new()
        local learner = Phase2Learner.new(adapter)
        local weights = {}
        local opts = {learning_rate = 0.05, max_weight_delta = 0.02, min_margin = 0.05, epsilon = 0.01}

        -- Load demo manually (we'll add loader later)
        local decision = {
            demonstrated_action = "RETRIEVE",
            state_snapshot = {
                task = {
                    task_type = "math",
                    complexity_estimate = 0.2,
                    input_length = 0.3,
                    entity_count = 0.0,
                    tool_requirements = {"calculator"}
                },
                self = {confidence = 0.3, steps_taken = 0, prev_action = nil}
            }
        }

        local metrics = learner:LearnFromDecision(decision, RULES, weights, opts)

        -- Should have scores
        assert.is_not_nil(metrics.score_star)
        assert.is_not_nil(metrics.score_comp)
        assert.is_equal(0, metrics.score_comp)  -- No competitor
    end)

    it("should handle coverage failure (no rules for demonstrated action)", function()
        local adapter = Phase1Adapter.new()
        local learner = Phase2Learner.new(adapter)
        local weights = {}
        local opts = {learning_rate = 0.05, max_weight_delta = 0.02, min_margin = 0.05, epsilon = 0.01}

        local decision = {
            demonstrated_action = "VERIFY",  -- No rules for VERIFY
            state_snapshot = {
                task = {task_type = "code", complexity_estimate = 0.7},
                self = {confidence = 0.5, steps_taken = 0, prev_action = nil}
            }
        }

        local metrics = learner:LearnFromDecision(decision, RULES, weights, opts)

        assert.is_false(metrics.updated)
        assert.is_true(metrics.uncovered)
        assert.is_equal("no_rules_for_demonstrated_action", metrics.reason)
    end)
end)
