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
