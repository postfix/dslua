describe("Phase1DecisionAdapter - NormalizeState", function()
    local Phase1Adapter

    setup(function()
        Phase1Adapter = require("poc.phase1_adapter")
    end)

    it("should normalize raw snapshot to state with task/self layers", function()
        local snapshot = {
            task = {
                task_type = "math",
                complexity_estimate = 0.2,
                input_length = 0.3,
                entity_count = 0.0,
                tool_requirements = {"calculator"}
            },
            self = {
                confidence = 0.5,
                steps_taken = 0,
                prev_action = nil
            }
        }

        local adapter = Phase1Adapter.new()
        local state = adapter:NormalizeState(snapshot)

        assert.is_not_nil(state.task)
        assert.is_equal("math", state.task.task_type)
        assert.is_equal(0.2, state.task.complexity_estimate)
        assert.is_not_nil(state.self)
        assert.is_equal(0.5, state.self.confidence)
        assert.is_equal(0, state.self.steps_taken)
    end)

    it("should apply defaults for missing optional fields", function()
        local snapshot = {
            task = {
                task_type = "general",
                complexity_estimate = 0.5
                -- Missing: input_length, entity_count, tool_requirements
            },
            self = {
                confidence = 0.7,
                steps_taken = 1
                -- Missing: prev_action
            }
        }

        local adapter = Phase1Adapter.new()
        local state = adapter:NormalizeState(snapshot)

        assert.is_equal(0.0, state.task.input_length)  -- Default
        assert.is_equal(0.0, state.task.entity_count)  -- Default
        assert.is_same({}, state.task.tool_requirements)  -- Default
        assert.is_nil(state.self.prev_action)  -- Default
    end)

    it("should be idempotent (normalizing twice returns same result)", function()
        local snapshot = {
            task = {task_type = "factual", complexity_estimate = 0.3},
            self = {confidence = 0.6, steps_taken = 0}
        }

        local adapter = Phase1Adapter.new()
        local state1 = adapter:NormalizeState(snapshot)
        local state2 = adapter:NormalizeState(state1)  -- Already normalized

        assert.is_equal(state1.task.task_type, state2.task.task_type)
        assert.is_equal(state1.self.confidence, state2.self.confidence)
    end)
end)

describe("Phase1DecisionAdapter - ComputeSalience", function()
    local Phase1Adapter

    setup(function()
        Phase1Adapter = require("poc.phase1_adapter")
    end)

    it("should return salience 1.0 when rule matches state", function()
        local rule = {
            id = "test_rule",
            key = "test_rule",
            conditions = {
                {"task_type", "==", "math"},
                {"complexity_estimate", "<", 0.5}
            }
        }

        local state = {
            task = {task_type = "math", complexity_estimate = 0.2},
            self = {confidence = 0.5, steps_taken = 0}
        }

        local adapter = Phase1Adapter.new()
        local salience, diag = adapter:ComputeSalience(rule, state, {salience_mode = "binary"})

        assert.is_equal(1.0, salience)
        assert.is_equal("binary", diag.mode)
        assert.is_false(diag.coerced)
        assert.is_equal(1.0, diag.raw)
    end)

    it("should return salience 0.0 when rule does not match state", function()
        local rule = {
            id = "test_rule",
            key = "test_rule",
            conditions = {
                {"task_type", "==", "factual"}
            }
        }

        local state = {
            task = {task_type = "math", complexity_estimate = 0.2},
            self = {confidence = 0.5, steps_taken = 0}
        }

        local adapter = Phase1Adapter.new()
        local salience, diag = adapter:ComputeSalience(rule, state, {salience_mode = "binary"})

        assert.is_equal(0.0, salience)
        assert.is_equal("binary", diag.mode)
        assert.is_false(diag.coerced)
        assert.is_equal(0.0, diag.raw)
    end)

    it("should evaluate all conditions with AND logic", function()
        local rule = {
            id = "test_rule",
            key = "test_rule",
            conditions = {
                {"task_type", "==", "math"},
                {"complexity_estimate", "<", 0.5},
                {"confidence", ">", 0.3}
            }
        }

        -- All conditions match
        local state_match = {
            task = {task_type = "math", complexity_estimate = 0.2},
            self = {confidence = 0.5, steps_taken = 0}
        }

        local adapter = Phase1Adapter.new()
        local salience1 = adapter:ComputeSalience(rule, state_match, {salience_mode = "binary"})
        assert.is_equal(1.0, salience1)

        -- One condition fails
        local state_fail = {
            task = {task_type = "math", complexity_estimate = 0.6},  -- >= 0.5
            self = {confidence = 0.5, steps_taken = 0}
        }

        local salience2 = adapter:ComputeSalience(rule, state_fail, {salience_mode = "binary"})
        assert.is_equal(0.0, salience2)
    end)

    it("should error on invalid salience_mode", function()
        local rule = {id = "test", key = "test", conditions = {}}
        local state = {task = {}, self = {}}
        local adapter = Phase1Adapter.new()

        assert.has_error(function()
            adapter:ComputeSalience(rule, state, {salience_mode = "invalid"})
        end, "Invalid salience_mode")
    end)
end)

describe("Phase1DecisionAdapter - FindMatchingRules", function()
    local Phase1Adapter

    setup(function()
        Phase1Adapter = require("poc.phase1_adapter")
    end)

    it("should return all rules matching action with weight and salience", function()
        local rules = {
            {
                id = "rule1",
                key = "rule1",
                conditions = {{"task_type", "==", "math"}},
                action = "RETRIEVE",
                default_weight = 0.8
            },
            {
                id = "rule2",
                key = "rule2",
                conditions = {{"task_type", "==", "math"}, {"complexity_estimate", "<", 0.5}},
                action = "REASON",
                default_weight = 0.7
            }
        }

        local weights = {rule1 = 0.8, rule2 = 0.7}
        local state = {
            task = {task_type = "math", complexity_estimate = 0.2},
            self = {confidence = 0.5, steps_taken = 0}
        }

        local adapter = Phase1Adapter.new()

        -- Find rules for RETRIEVE action
        local retrieve_matches = adapter:FindMatchingRules(state, "RETRIEVE", rules, weights)
        assert.is_equal(1, #retrieve_matches)
        assert.is_equal("rule1", retrieve_matches[1].key)
        assert.is_equal(0.8, retrieve_matches[1].weight)
        assert.is_equal(1.0, retrieve_matches[1].salience)

        -- Find rules for REASON action
        local reason_matches = adapter:FindMatchingRules(state, "REASON", rules, weights)
        assert.is_equal(1, #reason_matches)
        assert.is_equal("rule2", reason_matches[1].key)
    end)

    it("should use default_weight when key not in weights table", function()
        local rules = {
            {
                id = "rule1",
                key = "rule1",
                conditions = {{"task_type", "==", "math"}},
                action = "RETRIEVE",
                default_weight = 0.75
            }
        }

        local weights = {}  -- Empty weights table
        local state = {
            task = {task_type = "math", complexity_estimate = 0.2},
            self = {confidence = 0.5, steps_taken = 0}
        }

        local adapter = Phase1Adapter.new()
        local matches = adapter:FindMatchingRules(state, "RETRIEVE", rules, weights)

        assert.is_equal(1, #matches)
        assert.is_equal(0.75, matches[1].weight)
    end)

    it("should error when rule has no weight and no default_weight", function()
        local rules = {
            {
                id = "rule1",
                key = "rule1",
                conditions = {{"task_type", "==", "math"}},
                action = "RETRIEVE"
                -- No default_weight
            }
        }

        local weights = {}
        local state = {
            task = {task_type = "math", complexity_estimate = 0.2},
            self = {confidence = 0.5, steps_taken = 0}
        }

        local adapter = Phase1Adapter.new()

        assert.has_error(function()
            adapter:FindMatchingRules(state, "RETRIEVE", rules, weights)
        end, "Missing weight for rule")
    end)

    it("should return empty array when no rules match", function()
        local rules = {
            {
                id = "rule1",
                key = "rule1",
                conditions = {{"task_type", "==", "factual"}},
                action = "REASON",
                default_weight = 0.7
            }
        }

        local weights = {rule1 = 0.7}
        local state = {
            task = {task_type = "math", complexity_estimate = 0.2},  -- Doesn't match
            self = {confidence = 0.5, steps_taken = 0}
        }

        local adapter = Phase1Adapter.new()
        local matches = adapter:FindMatchingRules(state, "REASON", rules, weights)

        assert.is_equal(0, #matches)
    end)

    it("should preserve rules array order in returned matches", function()
        local rules = {
            {
                id = "rule1",
                key = "rule1",
                conditions = {{"task_type", "==", "math"}},
                action = "RETRIEVE",
                default_weight = 0.8
            },
            {
                id = "rule2",
                key = "rule2",
                conditions = {{"task_type", "==", "math"}},
                action = "RETRIEVE",
                default_weight = 0.7
            },
            {
                id = "rule3",
                key = "rule3",
                conditions = {{"task_type", "==", "math"}},
                action = "RETRIEVE",
                default_weight = 0.6
            }
        }

        local weights = {rule1 = 0.8, rule2 = 0.7, rule3 = 0.6}
        local state = {
            task = {task_type = "math", complexity_estimate = 0.2},
            self = {confidence = 0.5, steps_taken = 0}
        }

        local adapter = Phase1Adapter.new()
        local matches = adapter:FindMatchingRules(state, "RETRIEVE", rules, weights)

        assert.is_equal(3, #matches)
        assert.is_equal("rule1", matches[1].key)
        assert.is_equal("rule2", matches[2].key)
        assert.is_equal("rule3", matches[3].key)
    end)
end)
