-- specs/agents/ace_persistence_spec.lua
describe("ACE Persistence - ExportLearnedWeights", function()
  local ExportLearnedWeights, LoadWeightOverrides

  setup(function()
    local persistence = require("dslua.agents.ace_persistence")
    ExportLearnedWeights = persistence.ExportLearnedWeights
    LoadWeightOverrides = persistence.LoadWeightOverrides
  end)

  it("exports learned weights to JSON", function()
    local rules = {
      {id = 1, key = "rule1", default_weight = 0.8},
      {id = 2, key = "rule2", default_weight = 0.5}
    }
    local weights = {
      rule1 = 0.85,  -- Learned
      rule2 = 0.5    -- Unchanged (at default)
    }
    local filepath = "/tmp/test_weights.json"

    local success, err = ExportLearnedWeights(filepath, rules, weights)

    assert.is_true(success)
    assert.is_nil(err)

    -- Read file and verify content
    local f = io.open(filepath, "r")
    local content = f:read("*all")
    f:close()

    local json = require("dkjson")
    local data = json.decode(content)

    -- Only rule1 exported (changed from default)
    assert.is_equal(0.85, data.rule1)
    assert.is_nil(data.rule2)  -- Not exported (at default)

    -- Cleanup
    os.remove(filepath)
  end)

  it("loads weight overrides from JSON", function()
    local rules = {
      {id = 1, key = "rule1", default_weight = 0.8},
      {id = 2, key = "rule2", default_weight = 0.5}
    }

    -- Create test file
    local json = require("dkjson")
    local filepath = "/tmp/test_overrides.json"
    local f = io.open(filepath, "w")
    f:write(json.encode({rule1 = 0.95}))
    f:close()

    local overrides, err = LoadWeightOverrides(filepath, rules)

    assert.is_not_nil(overrides)
    assert.is_nil(err)
    assert.is_equal(0.95, overrides.rule1)
    assert.is_nil(overrides.rule2)

    -- Cleanup
    os.remove(filepath)
  end)

  it("returns error for non-numeric weights", function()
    local rules = {
      {id = 1, key = "rule1", default_weight = 0.8}
    }

    -- Create test file with invalid weight
    local json = require("dkjson")
    local filepath = "/tmp/test_invalid.json"
    local f = io.open(filepath, "w")
    f:write(json.encode({rule1 = "invalid"}))
    f:close()

    local overrides, err = LoadWeightOverrides(filepath, rules)

    assert.is_nil(overrides)
    assert.is_not_nil(err)
    assert.is_not_nil(err:match("expected number"))

    -- Cleanup
    os.remove(filepath)
  end)
end)
