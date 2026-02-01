describe("ACE Default Rules", function()
    it("should load default rule set", function()
        local rules = require("dslua.agents.ace_rules")

        assert.is_not_nil(rules)
        assert.is_true(#rules >= 5, "Should have at least 5 rules")
    end)

    it("should have all required rule fields", function()
        local rules = require("dslua.agents.ace_rules")

        for _, rule in ipairs(rules) do
            assert.is_not_nil(rule.name, "Rule should have name")
            assert.is_not_nil(rule.action, "Rule should have action")
            assert.is_not_nil(rule.default_weight, "Rule should have default_weight")
            assert.is_not_nil(rule.conditions, "Rule should have conditions")
            assert.is_not_nil(rule.id, "Rule should have id")
        end
    end)

    it("should have rule for complex task decomposition", function()
        local rules = require("dslua.agents.ace_rules")

        local found = false
        for _, rule in ipairs(rules) do
            if rule.name == "complex_decomposition" then
                found = true
                assert.is.equal("DECOMPOSE", rule.action)
                assert.is_true(rule.default_weight > 0.7, "Should have high default_weight")
                break
            end
        end

        assert.is_true(found, "Should have complex_decomposition rule")
    end)

    it("should have rule for factual retrieval", function()
        local rules = require("dslua.agents.ace_rules")

        local found = false
        for _, rule in ipairs(rules) do
            if rule.name == "factual_retrieval" then
                found = true
                assert.is.equal("RETRIEVE", rule.action)
                break
            end
        end

        assert.is_true(found, "Should have factual_retrieval rule")
    end)

    it("should have fallback rule with low weight", function()
        local rules = require("dslua.agents.ace_rules")

        local found = false
        for _, rule in ipairs(rules) do
            if rule.name == "default_reason_terminate" then
                found = true
                assert.is.equal("REASON", rule.action)
                assert.is_true(rule.default_weight < 0.5, "Should have low default_weight")
                break
            end
        end

        assert.is_true(found, "Should have default fallback rule")
    end)
end)
