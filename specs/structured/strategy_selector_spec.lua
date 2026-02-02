-- specs/structured/strategy_selector_spec.lua
-- Tests for dslua/structured/strategy_selector.lua

local StrategySelector = require("dslua.structured.strategy_selector")
local Schema = require("dslua.structured.schema")

describe("Strategy Selector", function()

  describe("Auto-strategy selection", function()
    it("should select instructional for flat schemas with <=5 fields", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"},
        email = {type = "string"}
      })

      local strategy = StrategySelector.select_strategy(schema, "auto")

      assert.is_equal("instructional", strategy)
    end)

    it("should select few-shot for schemas with nested objects", function()
      local schema = Schema.Object({
        name = {type = "string"},
        address = {
          type = "object",
          properties = {
            street = {type = "string"},
            city = {type = "string"}
          }
        }
      })

      local strategy = StrategySelector.select_strategy(schema, "auto")

      assert.is_equal("few-shot", strategy)
    end)

    it("should select few-shot for schemas with arrays", function()
      local schema = Schema.Object({
        name = {type = "string"},
        tags = {
          type = "array",
          items = {type = "string"}
        }
      })

      local strategy = StrategySelector.select_strategy(schema, "auto")

      assert.is_equal("few-shot", strategy)
    end)

    it("should select few-shot for schemas with enum constraints", function()
      local schema = Schema.Object({
        status = {
          type = "string",
          enum = {"active", "inactive"}
        }
      })

      local strategy = StrategySelector.select_strategy(schema, "auto")

      assert.is_equal("few-shot", strategy)
    end)

    it("should select few-shot for schemas with pattern constraints", function()
      local schema = Schema.Object({
        email = {
          type = "string",
          pattern = "^[^@]+@[^@]+$"
        }
      })

      local strategy = StrategySelector.select_strategy(schema, "auto")

      assert.is_equal("few-shot", strategy)
    end)

    it("should select instructional when token budget constrained", function()
      local schema = Schema.Object({
        field1 = {type = "string"},
        field2 = {type = "string"},
        field3 = {type = "string"},
        field4 = {type = "string"},
        field5 = {type = "string"}
      })

      local strategy = StrategySelector.select_strategy(schema, "auto", {
        token_budget_threshold = 100
      })

      assert.is_equal("instructional", strategy)
    end)
  end)

  describe("Explicit strategy selection", function()
    it("should respect explicit few-shot selection", function()
      local schema = Schema.Object({
        name = {type = "string"}
      })

      local strategy = StrategySelector.select_strategy(schema, "few-shot")

      assert.is_equal("few-shot", strategy)
    end)

    it("should respect explicit instructional selection", function()
      local schema = Schema.Object({
        nested = {
          type = "object",
          properties = {
            field = {type = "string"}
          }
        }
      })

      local strategy = StrategySelector.select_strategy(schema, "instructional")

      assert.is_equal("instructional", strategy)
    end)
  end)

  describe("Schema analysis", function()
    it("should detect flat schemas correctly", function()
      local schema = Schema.Object({
        field1 = {type = "string"},
        field2 = {type = "integer"}
      })

      local analysis = StrategySelector.analyze_schema(schema)

      assert.is_true(analysis.is_flat)
      assert.is_false(analysis.has_nested_objects)
      assert.is_false(analysis.has_arrays)
    end)

    it("should detect nested objects correctly", function()
      local schema = Schema.Object({
        user = {
          type = "object",
          properties = {
            name = {type = "string"}
          }
        }
      })

      local analysis = StrategySelector.analyze_schema(schema)

      assert.is_false(analysis.is_flat)
      assert.is_true(analysis.has_nested_objects)
    end)

    it("should detect arrays correctly", function()
      local schema = Schema.Object({
        tags = {
          type = "array",
          items = {type = "string"}
        }
      })

      local analysis = StrategySelector.analyze_schema(schema)

      assert.is_false(analysis.is_flat)
      assert.is_true(analysis.has_arrays)
    end)

    it("should count fields correctly", function()
      local schema = Schema.Object({
        field1 = {type = "string"},
        field2 = {type = "string"},
        field3 = {type = "string"}
      })

      local analysis = StrategySelector.analyze_schema(schema)

      assert.is_equal(3, analysis.field_count)
    end)

    it("should detect constraints correctly", function()
      local schema = Schema.Object({
        status = {
          type = "string",
          enum = {"active", "inactive"}
        },
        email = {
          type = "string",
          pattern = "^.*@.*$"
        }
      })

      local analysis = StrategySelector.analyze_schema(schema)

      assert.is_true(analysis.has_enum)
      assert.is_true(analysis.has_pattern)
    end)
  end)

  describe("Token budget consideration", function()
    it("should prefer instructional when budget is tight", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"},
        email = {type = "string"}
      })

      local opts = {
        token_budget_threshold = 50
      }

      local strategy = StrategySelector.select_strategy(schema, "auto", opts)

      assert.is_equal("instructional", strategy)
    end)

    it("should use few-shot when budget allows", function()
      local schema = Schema.Object({
        user = {
          type = "object",
          properties = {
            name = {type = "string"}
          }
        }
      })

      local opts = {
        token_budget_threshold = 1000
      }

      local strategy = StrategySelector.select_strategy(schema, "auto", opts)

      assert.is_equal("few-shot", strategy)
    end)
  end)

  describe("Edge cases", function()
    it("should handle empty schema", function()
      local schema = Schema.Object({})

      local strategy = StrategySelector.select_strategy(schema, "auto")

      assert.is_not_nil(strategy)
    end)

    it("should handle schemas with only optional fields", function()
      local schema = Schema.Object({
        optional1 = {type = "string"},
        optional2 = {type = "integer"}
      })

      local strategy = StrategySelector.select_strategy(schema, "auto")

      assert.is_not_nil(strategy)
    end)

    it("should handle schemas with all constraint types", function()
      local schema = Schema.Object({
        enum_field = {
          type = "string",
          enum = {"a", "b"}
        },
        pattern_field = {
          type = "string",
          pattern = "^%d+$"
        },
        nested = {
          type = "object",
          properties = {
            value = {type = "string"}
          }
        },
        array_field = {
          type = "array",
          items = {type = "string"}
        }
      })

      local strategy = StrategySelector.select_strategy(schema, "auto")

      -- Should choose few-shot due to complexity
      assert.is_equal("few-shot", strategy)
    end)
  end)

  describe("Token estimation", function()
    it("should estimate tokens for simple schema", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local tokens = StrategySelector.estimate_tokens(schema)

      assert.is_true(tokens > 0)
      assert.is_true(tokens < 1000)
    end)

    it("should estimate tokens for schema with enum", function()
      local schema = Schema.Object({
        status = {
          type = "string",
          enum = {"active", "inactive", "pending"}
        }
      })

      local tokens = StrategySelector.estimate_tokens(schema)

      assert.is_true(tokens > 0)
      -- Should be higher due to enum values
      assert.is_true(tokens > 10)
    end)

    it("should estimate tokens for schema with pattern", function()
      local schema = Schema.Object({
        email = {
          type = "string",
          pattern = "^[^@]+@[^@]+$"
        }
      })

      local tokens = StrategySelector.estimate_tokens(schema)

      assert.is_true(tokens > 0)
      -- Should include pattern length
      assert.is_true(tokens > #'^[^@]+@[^@]+$')
    end)

    it("should estimate tokens for nested schema", function()
      local schema = Schema.Object({
        user = {
          type = "object",
          properties = {
            name = {type = "string"},
            profile = {
              type = "object",
              properties = {
                bio = {type = "string"}
              }
            }
          }
        }
      })

      local tokens = StrategySelector.estimate_tokens(schema)

      assert.is_true(tokens > 0)
      -- Should account for nested structure
      assert.is_true(tokens > 20)
    end)

    it("should estimate tokens for array schema", function()
      local schema = Schema.Object({
        tags = {
          type = "array",
          items = {type = "string"}
        }
      })

      local tokens = StrategySelector.estimate_tokens(schema)

      assert.is_true(tokens > 0)
      assert.is_true(tokens < 1000)
    end)

    it("should estimate tokens for complex schema", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"},
        email = {
          type = "string",
          pattern = "^[^@]+@[^@]+$"
        },
        status = {
          type = "string",
          enum = {"active", "inactive"}
        },
        tags = {
          type = "array",
          items = {type = "string"}
        }
      })

      local tokens = StrategySelector.estimate_tokens(schema)

      assert.is_true(tokens > 0)
      -- Complex schema should have higher estimate
      assert.is_true(tokens > 50)
    end)
  end)

end)
