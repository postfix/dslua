describe("ACE Base Class", function()
    local Field = require("dslua.core.field")
    local Signature = require("dslua.core.signature")
    local Context = require("dslua.core.context")
    local ACE = require("dslua.agents.ace")

    it("should create ACE with module and configuration", function()
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local module = require("dslua.modules.predict").new(signature)
        local rules = {}

        local ace = ACE.new(module, {
            rules = rules,
            learning_mode = "passive"
        })

        assert.is_not_nil(ace)
        assert.is.equal(module, ace:_Module())
        assert.is.equal("passive", ace._config.learning_mode)
    end)

    it("should initialize three-layer state structure", function()
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local module = require("dslua.modules.predict").new(signature)
        local ace = ACE.new(module, {rules = {}})

        local state = ace:_InitializeState({question = "test"})

        assert.is_not_nil(state.task)        -- Layer 1
        assert.is_not_nil(state.self)         -- Layer 2
        assert.is_not_nil(state.history)      -- Layer 3
    end)

    it("should normalize task features to [0,1]", function()
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local module = require("dslua.modules.predict").new(signature)
        local ace = ACE.new(module, {rules = {}})

        local state = ace:_InitializeState({question = "What is the capital of France?"})

        assert.is_true(state.task.input_length >= 0.0)
        assert.is_true(state.task.input_length <= 1.0)
    end)

    it("should initialize empty self-monitoring state", function()
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local module = require("dslua.modules.predict").new(signature)
        local ace = ACE.new(module, {rules = {}})

        local state = ace:_InitializeState({question = "test"})

        assert.is.equal(0.5, state.self.confidence)  -- default
        assert.is.equal(0, #state.self.action_history)
        assert.is.equal(0, state.self.steps_taken)
    end)

    it("should initialize empty performance history", function()
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )
        local module = require("dslua.modules.predict").new(signature)
        local ace = ACE.new(module, {rules = {}})

        local state = ace:_InitializeState({question = "test"})

        assert.is_not_nil(state.history.success_rate)
        assert.is_not_nil(state.history.tool_effectiveness)
        assert.is.equal(0, state.history.total_executions)
    end)
end)
