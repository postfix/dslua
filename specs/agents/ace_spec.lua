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

describe("ACE Rule Matching", function()
    local ACE = require("dslua.agents.ace")

    setup(function()
        local signature = require("dslua.core.signature").new(
            {require("dslua.core.field").new("question")},
            {require("dslua.core.field").new("answer")}
        )
        local module = require("dslua.modules.predict").new(signature)
        _ace = ACE.new(module, {rules = {}})
    end)

    it("should match rules with simple equality conditions", function()
        local rules = {
            {
                key = "test_rule",
                name = "test_rule",
                conditions = {
                    {feature = "task_type", op = "==", value = "math"}
                },
                action = "USE_CALCULATOR",
                default_weight = 0.9,
                id = 1
            }
        }

        local state = {
            task = {task_type = "math"},
            self = {confidence = 0.5},
            history = {}
        }

        local matches = _ace:_FindMatchingRules(state, rules)
        assert.is.equal(1, #matches)
        assert.is.equal("test_rule", matches[1].name)
    end)

    it("should match rules with greater-than conditions", function()
        local rules = {
            {
                key = "complexity_rule",
                name = "complexity_rule",
                conditions = {
                    {feature = "complexity_estimate", op = ">", threshold = 0.7}
                },
                action = "DECOMPOSE",
                default_weight = 0.8,
                id = 2
            }
        }

        local state = {
            task = {complexity_estimate = 0.85},
            self = {confidence = 0.5},
            history = {}
        }

        local matches = _ace:_FindMatchingRules(state, rules)
        assert.is.equal(1, #matches)
    end)

    it("should match rules with less-than conditions", function()
        local rules = {
            {
                key = "confidence_rule",
                name = "confidence_rule",
                conditions = {
                    {feature = "confidence", op = "<", threshold = 0.6}
                },
                action = "VERIFY",
                default_weight = 0.7,
                id = 3
            }
        }

        local state = {
            task = {},
            self = {confidence = 0.4},
            history = {}
        }

        local matches = _ace:_FindMatchingRules(state, rules)
        assert.is.equal(1, #matches)
    end)

    it("should not match rules that fail conditions", function()
        local rules = {
            {
                key = "high_complexity",
                name = "high_complexity",
                conditions = {
                    {feature = "complexity_estimate", op = ">", threshold = 0.7}
                },
                action = "DECOMPOSE",
                default_weight = 0.8,
                id = 4
            }
        }

        local state = {
            task = {complexity_estimate = 0.5},
            self = {confidence = 0.5},
            history = {}
        }

        local matches = _ace:_FindMatchingRules(state, rules)
        assert.is.equal(0, #matches)
    end)

    it("should score rules by weight × salience", function()
        local rules = {
            {
                key = "strong_match",
                name = "strong_match",
                conditions = {{feature = "confidence", op = "<", threshold = 0.6}},
                action = "VERIFY",
                default_weight = 0.9,
                id = 5
            }
        }

        local state = {
            task = {},
            self = {confidence = 0.3},  -- well below threshold
            history = {}
        }

        local matches = _ace:_FindMatchingRules(state, rules)
        local scores = _ace:_ScoreRules(matches, state)

        -- Salience based on how far past threshold (0.6 - 0.3 = 0.3)
        -- Score = 0.9 × salience (currently 1.0)
        -- scores is a table with rules as keys
        local score_for_rule = scores[matches[1]]
        assert.is_not_nil(score_for_rule)
        assert.is_true(score_for_rule > 0)
        assert.is_true(score_for_rule <= 0.9)
    end)
end)

describe("ACE Action Selection", function()
    local ACE = require("dslua.agents.ace")

    setup(function()
        local signature = require("dslua.core.signature").new(
            {require("dslua.core.field").new("question")},
            {require("dslua.core.field").new("answer")}
        )
        local module = require("dslua.modules.predict").new(signature)
        _ace = ACE.new(module, {rules = {}})
    end)

    it("should select highest-scoring action", function()
        local rules = {
            {key = "test_decompose", action = "DECOMPOSE", default_weight = 0.9, id = 1, conditions = {}},
            {key = "test_answer", action = "ANSWER", default_weight = 0.6, id = 2, conditions = {}}
        }

        local state = {task = {}, self = {}, history = {}}
        local action = _ace:_SelectAction(state, rules)

        assert.is.equal("DECOMPOSE", action)
    end)

    it("should use fallback when no rules match", function()
        local rules = {}  -- No rules

        local state = {task = {}, self = {}, history = {}}
        local action = _ace:_SelectAction(state, rules)

        assert.is.equal("REASON", action)  -- Default fallback
    end)

    it("should break ties by recency (higher ID)", function()
        local rules = {
            {key = "test_old", action = "OLD", default_weight = 0.8, id = 1, conditions = {}},
            {key = "test_new", action = "NEW", default_weight = 0.8, id = 10, conditions = {}}
        }

        local state = {task = {}, self = {}, history = {}}
        local action = _ace:_SelectAction(state, rules)

        assert.is.equal("NEW", action)  -- Higher ID wins
    end)

    it("should record decision with competing alternatives", function()
        local rules = {
            {key = "test_win", action = "WIN", default_weight = 0.9, id = 1, conditions = {}},
            {key = "test_lose", action = "LOSE", default_weight = 0.7, id = 2, conditions = {}}
        }

        local state = {task = {}, self = {}, history = {}}
        local decision = _ace:_DecideWithLogging(state, rules)

        assert.is.equal("WIN", decision.action)
        assert.is_not_nil(decision.competing_actions)
        assert.is_true(#decision.competing_actions >= 1)
    end)
end)

describe("ACE Execution Loop", function()
    local Field = require("dslua.core.field")
    local Signature = require("dslua.core.signature")
    local Context = require("dslua.core.context")
    local ACE = require("dslua.agents.ace")

    it("should execute REASON action by delegating to module", function()
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Answer: 42"}
            end
        }

        local module = require("dslua.modules.predict").new(signature)
        module:WithLLM(mock_llm)

        local rules = {
            {key = "test_reason", action = "REASON", default_weight = 0.9, id = 1, conditions = {}}
        }

        local ace = ACE.new(module, {rules = rules})
        local ctx = Context.new({})

        local result = ace:Execute(ctx, {question = "What is 6*7?"})

        assert.is.equal("42", result.answer)
        assert.is.equal(1, result.stats.steps_taken)
    end)

    it("should track action history during execution", function()
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Answer: test"}
            end
        }

        local module = require("dslua.modules.predict").new(signature)
        module:WithLLM(mock_llm)

        local rules = {
            {key = "test_reason", action = "REASON", default_weight = 0.9, id = 1, conditions = {}}
        }

        local ace = ACE.new(module, {rules = rules, max_steps = 5})
        local ctx = Context.new({})

        local result = ace:Execute(ctx, {question = "test"})

        assert.is_not_nil(result.stats.action_history)
        assert.is_true(#result.stats.action_history >= 1)
    end)

    it("should timeout when max_steps exceeded", function()
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local module = {
            Process = function(self, ctx, input)
                -- Always return DECOMPOSE (never terminates)
                return {answer = nil, action = "DECOMPOSE"}
            end,
            Signature = function() return signature end
        }

        local rules = {
            {key = "test_decompose", action = "DECOMPOSE", default_weight = 0.9, id = 1, conditions = {}}
        }

        local ace = ACE.new(module, {rules = rules, max_steps = 3})
        local ctx = Context.new({})

        local result = ace:Execute(ctx, {question = "test"})

        assert.is.equal("TIMEOUT", result.termination_reason)
    end)

    it("should return result on TERMINATE action", function()
        local signature = Signature.new(
            {Field.new("question")},
            {Field.new("answer")}
        )

        local mock_llm = {
            Complete = function(self, ctx, prompt)
                return {content = "Answer: Paris"}
            end
        }

        local module = require("dslua.modules.predict").new(signature)
        module:WithLLM(mock_llm)

        local rules = {
            {key = "test_terminate", action = "TERMINATE", default_weight = 0.9, id = 1, conditions = {}}
        }

        local ace = ACE.new(module, {rules = rules})
        local ctx = Context.new({})

        local result = ace:Execute(ctx, {question = "Capital of France?"})

        assert.is.equal("Paris", result.answer)
        assert.is.equal("SUCCESS", result.termination_reason)
    end)
end)
