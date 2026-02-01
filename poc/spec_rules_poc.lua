-- poc/spec_rules_poc.lua
describe("POC Rules", function()
    local RULES

    setup(function()
        RULES = require("poc.rules_poc")
    end)

    it("should export 5 rules", function()
        assert.is_equal(5, #RULES)
    end)

    it("should have required fields in each rule", function()
        for i, rule in ipairs(RULES) do
            assert.is_not_nil(rule.id, string.format("Rule %d missing id", i))
            assert.is_not_nil(rule.key, string.format("Rule %d missing key", i))
            assert.is_not_nil(rule.conditions, string.format("Rule %d missing conditions", i))
            assert.is_not_nil(rule.action, string.format("Rule %d missing action", i))
            assert.is_not_nil(rule.default_weight, string.format("Rule %d missing default_weight", i))
        end
    end)

    it("should have math_use_calculator rule targeting RETRIEVE", function()
        local rule = RULES[1]
        assert.is_equal("math_use_calculator", rule.id)
        assert.is_equal("math_use_calculator", rule.key)
        assert.is_equal("RETRIEVE", rule.action)
        assert.is_equal(0.8, rule.default_weight)
        assert.is_equal(2, #rule.conditions)
    end)

    it("should have factual_reason_direct rule targeting REASON with weight 0.700", function()
        local rule = RULES[2]
        assert.is_equal("factual_reason_direct", rule.id)
        assert.is_equal("REASON", rule.action)
        assert.is_equal(0.700, rule.default_weight)
    end)

    it("should have factual_use_search rule targeting RETRIEVE with weight 0.695", function()
        local rule = RULES[3]
        assert.is_equal("factual_use_search", rule.id)
        assert.is_equal("RETRIEVE", rule.action)
        assert.is_equal(0.695, rule.default_weight)
    end)

    it("should have fallback_reason scoped to general task_type", function()
        local rule = RULES[5]
        assert.is_equal("fallback_reason", rule.id)
        assert.is_equal("REASON", rule.action)

        -- Check that first condition is task_type == "general"
        assert.is_equal("task_type", rule.conditions[1][1])
        assert.is_equal("==", rule.conditions[1][2])
        assert.is_equal("general", rule.conditions[1][3])
    end)
end)
