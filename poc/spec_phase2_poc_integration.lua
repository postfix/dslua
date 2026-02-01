-- poc/spec_phase2_poc_integration.lua
describe("ACE Phase 2 POC - Integration Tests", function()
    local Phase2Learner, Phase1Adapter, RULES

    setup(function()
        Phase2Learner = require("poc.ace_phase2_poc")
        Phase1Adapter = require("poc.phase1_adapter")
        RULES = require("poc.rules_poc")
    end)

    local ACTIONS_ORDER = {"REASON", "RETRIEVE", "DECOMPOSE", "SYNTHESIZE", "VERIFY", "TERMINATE"}

    -- Helper to copy weights
    local function copy_weights(weights)
        local copy = {}
        for k, v in pairs(weights) do
            copy[k] = v
        end
        return copy
    end

    it("all scores zero predicts REASON (fallback tie-breaking)", function()
        -- Create state where NO rules match (all scores 0)
        local empty_state = {
            task = {
                task_type = "unknown_type",  -- No rules match this
                complexity_estimate = 0.5,
                input_length = 0.0,
                entity_count = 0.0
            },
            self = {
                confidence = 0.5,
                steps_taken = 0,
                prev_action = nil
            }
        }

        local adapter = Phase1Adapter.new()
        local weights = {}
        local scores = adapter:ScoreActions(empty_state, RULES, weights, ACTIONS_ORDER)

        -- All scores should be 0
        for action, score in pairs(scores) do
            assert.is_equal(0, score, string.format("Action %s should have score 0", action))
        end

        -- Prediction should be REASON (first in ACTIONS_ORDER)
        local predicted = adapter:PredictAction(scores, ACTIONS_ORDER)
        assert.is_equal("REASON", predicted, "All-zero scores should fallback to first action in ACTIONS_ORDER")
    end)

    it("Demo 1: no competitor produces increase-only update", function()
        local adapter = Phase1Adapter.new()
        local learner = Phase2Learner.new(adapter)

        local initial_weights = {
            math_use_calculator = 0.04,
            factual_reason_direct = 0.700,
            factual_use_search = 0.695,
            general_retrieve_when_complex = 0.8,
            fallback_reason = 0.3
        }
        local weights = copy_weights(initial_weights)

        -- Ensure default_weight doesn't override table values
        -- (This tests the learning algorithm, not the weight resolution)
        for i, rule in ipairs(RULES) do
            if weights[rule.key] == nil then
                weights[rule.key] = rule.default_weight
            end
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

        -- Validate invariants
        assert.is_true(metrics.updated)
        assert.is_equal(0, metrics.score_comp)
        assert.is_equal(0, metrics.clamp_events.dec.count)  -- No decreases

        -- Weight should increase
        assert.is_true(weights["math_use_calculator"] > initial_weights["math_use_calculator"])

        -- Delta should be bounded
        local actual_delta = weights["math_use_calculator"] - initial_weights["math_use_calculator"]
        assert.is_true(actual_delta <= opts.max_weight_delta)
    end)

    it("Demo 2: epsilon-band aggregates competitors correctly", function()
        local adapter = Phase1Adapter.new()
        local learner = Phase2Learner.new(adapter)

        local weights = {
            math_use_calculator = 0.04,
            factual_reason_direct = 0.700,
            factual_use_search = 0.695,
            general_retrieve_when_complex = 0.8,
            fallback_reason = 0.3
        }

        -- Ensure default_weight doesn't override table values
        for i, rule in ipairs(RULES) do
            if weights[rule.key] == nil then
                weights[rule.key] = rule.default_weight
            end
        end

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

        -- Epsilon-band should include RETRIEVE
        assert.is_equal(1, metrics.comp_band_size)

        -- Both rules should have weight changes
        local initial_reason = 0.700
        local initial_search = 0.695
        assert.is_not_equal(initial_reason, weights["factual_reason_direct"])
        assert.is_not_equal(initial_search, weights["factual_use_search"])

        -- REASON should increase, RETRIEVE should decrease
        assert.is_true(weights["factual_reason_direct"] > initial_reason)
        assert.is_true(weights["factual_use_search"] < initial_search)
    end)

    it("Demo 3: margin saturation clamps delta_total", function()
        local adapter = Phase1Adapter.new()
        local learner = Phase2Learner.new(adapter)

        local weights = {
            math_use_calculator = 0.04,
            factual_reason_direct = 0.700,
            factual_use_search = 0.695,
            general_retrieve_when_complex = 0.8,
            fallback_reason = 0.3
        }

        -- Ensure default_weight doesn't override table values
        for i, rule in ipairs(RULES) do
            if weights[rule.key] == nil then
                weights[rule.key] = rule.default_weight
            end
        end

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

        -- Negative margin (competitor much stronger)
        assert.is_true(metrics.margin < 0)

        -- delta_total should be clamped to max_weight_delta
        assert.is_equal(opts.max_weight_delta, metrics.delta_total)

        -- Should have at least one clamp event
        assert.is_true(metrics.clamp_events.inc.count > 0 or metrics.clamp_events.dec.count > 0)
    end)

    it("Demo 4: coverage failure reports uncovered", function()
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
            demonstrated_action = "VERIFY",
            state_snapshot = {
                task = {task_type = "code", complexity_estimate = 0.7},
                self = {confidence = 0.5, steps_taken = 0, prev_action = nil}
            }
        }

        local metrics = learner:LearnFromDecision(decision, RULES, weights, opts)

        assert.is_false(metrics.updated)
        assert.is_true(metrics.uncovered)
        assert.is_equal("VERIFY", metrics.demonstrated_action)
        assert.is_equal("no_rules_for_demonstrated_action", metrics.reason)

        -- No weights should change
        assert.is_equal(0.8, weights["math_use_calculator"])
        assert.is_equal(0.700, weights["factual_reason_direct"])
    end)

    it("determinism: 10 runs produce identical results", function()
        local adapter = Phase1Adapter.new()
        local learner = Phase2Learner.new(adapter)

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

        -- Run 10 times
        local results = {}
        for i = 1, 10 do
            local weights = {
                math_use_calculator = 0.04,
                factual_reason_direct = 0.700,
                factual_use_search = 0.695,
                general_retrieve_when_complex = 0.8,
                fallback_reason = 0.3
            }
            -- Ensure default_weight doesn't override table values
            for _, rule in ipairs(RULES) do
                if weights[rule.key] == nil then
                    weights[rule.key] = rule.default_weight
                end
            end
            results[i] = learner:LearnFromDecision(decision, RULES, weights, opts)
        end

        -- All results identical
        for i = 2, 10 do
            assert.is_equal(results[1].delta_total, results[i].delta_total)
            assert.is_equal(results[1].margin, results[i].margin)
            assert.is_equal(results[1].comp_band_size, results[i].comp_band_size)
            assert.is_equal(results[1].score_star, results[i].score_star)
            assert.is_equal(results[1].score_comp, results[i].score_comp)
        end
    end)

    it("max delta per decision is respected", function()
        local adapter = Phase1Adapter.new()
        local learner = Phase2Learner.new(adapter)

        local weights = {
            math_use_calculator = 0.04,
            factual_reason_direct = 0.700,
            factual_use_search = 0.695,
            general_retrieve_when_complex = 0.8,
            fallback_reason = 0.3
        }

        -- Ensure default_weight doesn't override table values
        for i, rule in ipairs(RULES) do
            if weights[rule.key] == nil then
                weights[rule.key] = rule.default_weight
            end
        end

        local opts = {
            learning_rate = 0.05,
            max_weight_delta = 0.02,
            min_margin = 0.05,
            epsilon = 0.01,
            salience_mode = "binary"
        }

        -- Large negative margin case
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

        local initial_fallback = weights["fallback_reason"]
        local initial_retrieve = weights["general_retrieve_when_complex"]

        local metrics = learner:LearnFromDecision(decision, RULES, weights, opts)

        -- Check that no single weight change exceeds max_weight_delta
        local max_change = 0
        for key, old_w in pairs({fallback_reason = initial_fallback, general_retrieve_when_complex = initial_retrieve}) do
            local change = math.abs(weights[key] - old_w)
            if change > max_change then
                max_change = change
            end
        end

        assert.is_true(max_change <= opts.max_weight_delta + 0.0001, string.format("Max change %f exceeds %f", max_change, opts.max_weight_delta))
    end)
end)
