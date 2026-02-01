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
        -- This demo has sufficient margin (0.8 > 0.05), so no update
        assert.is_equal("sufficient_margin", metrics.reason)
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

describe("Phase2Learner - Complete Learning Loop", function()
    local Phase2Learner, Phase1Adapter, RULES

    setup(function()
        Phase2Learner = require("poc.ace_phase2_poc")
        Phase1Adapter = require("poc.phase1_adapter")
        RULES = require("poc.rules_poc")
    end)

    local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}

    it("no competitor demo produces increase-only update", function()
        local adapter = Phase1Adapter.new()
        local learner = Phase2Learner.new(adapter)

        -- Use smaller initial weight to avoid sufficient margin early return
        local initial_weights = {
            math_use_calculator = 0.04,  -- Small enough that margin < 0.05
            factual_reason_direct = 0.700,
            factual_use_search = 0.695,
            general_retrieve_when_complex = 0.8,
            fallback_reason = 0.3
        }
        local weights = {}
        for k, v in pairs(initial_weights) do
            weights[k] = v
        end

        local opts = {
            learning_rate = 0.05,
            max_weight_delta = 0.02,
            min_margin = 0.05,
            epsilon = 0.01,
            salience_mode = "binary"
        }

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

        assert.is_true(metrics.updated)
        assert.is_equal(0, metrics.score_comp)
        assert.is_equal(0, metrics.clamp_events.dec.count)

        -- Weight for math_use_calculator should increase
        assert.is_true(weights["math_use_calculator"] > initial_weights["math_use_calculator"])
    end)

    it("epsilon-band demo aggregates competitors correctly", function()
        local adapter = Phase1Adapter.new()
        local learner = Phase2Learner.new(adapter)

        local weights = {
            math_use_calculator = 0.8,
            factual_reason_direct = 0.700,
            factual_use_search = 0.695,
            general_retrieve_when_complex = 0.8,
            fallback_reason = 0.3
        }

        local opts = {
            learning_rate = 0.05,
            max_weight_delta = 0.02,
            min_margin = 0.05,
            epsilon = 0.01,
            salience_mode = "binary"
        }

        local decision = {
            demonstrated_action = "REASON",
            state_snapshot = {
                task = {
                    task_type = "factual",
                    complexity_estimate = 0.3,
                    input_length = 0.5,
                    entity_count = 0.4
                },
                self = {confidence = 0.7, steps_taken = 0, prev_action = nil}
            }
        }

        local metrics = learner:LearnFromDecision(decision, RULES, weights, opts)

        assert.is_true(metrics.updated)
        assert.is_equal(1, metrics.comp_band_size)  -- Only RETRIEVE is a competitor in the band
    end)

    it("margin saturation demo clamps delta_total", function()
        local adapter = Phase1Adapter.new()
        local learner = Phase2Learner.new(adapter)

        local weights = {
            math_use_calculator = 0.8,
            factual_reason_direct = 0.700,
            factual_use_search = 0.695,
            general_retrieve_when_complex = 0.8,
            fallback_reason = 0.3
        }

        local opts = {
            learning_rate = 0.05,
            max_weight_delta = 0.02,
            min_margin = 0.05,
            epsilon = 0.01,
            salience_mode = "binary"
        }

        local decision = {
            demonstrated_action = "REASON",
            state_snapshot = {
                task = {
                    task_type = "general",
                    complexity_estimate = 0.9
                },
                self = {confidence = 0.1, steps_taken = 0, prev_action = nil}
            }
        }

        local metrics = learner:LearnFromDecision(decision, RULES, weights, opts)

        assert.is_true(metrics.updated)
        assert.is_true(metrics.margin < 0)  -- Negative margin
        assert.is_equal(opts.max_weight_delta, metrics.delta_total)  -- Clamped
    end)

    it("all action iteration is deterministic", function()
        local adapter = Phase1Adapter.new()
        local learner = Phase2Learner.new(adapter)

        local weights = {
            math_use_calculator = 0.8,
            factual_reason_direct = 0.700,
            factual_use_search = 0.695,
            general_retrieve_when_complex = 0.8,
            fallback_reason = 0.3
        }

        local opts = {
            learning_rate = 0.05,
            max_weight_delta = 0.02,
            min_margin = 0.05,
            epsilon = 0.01,
            salience_mode = "binary"
        }

        local decision = {
            demonstrated_action = "REASON",
            state_snapshot = {
                task = {
                    task_type = "factual",
                    complexity_estimate = 0.3,
                    input_length = 0.5,
                    entity_count = 0.4
                },
                self = {confidence = 0.7, steps_taken = 0, prev_action = nil}
            }
        }

        -- Run learning 10 times with same inputs
        local results = {}
        for i = 1, 10 do
            local weights_copy = {}
            for k, v in pairs(weights) do
                weights_copy[k] = v
            end
            results[i] = learner:LearnFromDecision(decision, RULES, weights_copy, opts)
        end

        -- All results should be identical
        for i = 2, 10 do
            assert.is_equal(results[1].delta_total, results[i].delta_total)
            assert.is_equal(results[1].comp_band_size, results[i].comp_band_size)
        end
    end)
end)
