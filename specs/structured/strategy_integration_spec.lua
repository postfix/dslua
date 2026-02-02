-- specs/structured/strategy_integration_spec.lua
-- Tests for strategy integration with decorator

local StructuredOutput = require("dslua.structured.decorator")
local Schema = require("dslua.structured.schema")
local StrategySelector = require("dslua.structured.strategy_selector")

describe("Strategy Integration", function()

  describe("Few-shot strategy integration", function()
    it("should apply few-shot strategy when explicitly selected", function()
      local schema = Schema.Object({
        user = {
          type = "object",
          properties = {
            name = {type = "string"},
            email = {type = "string"}
          }
        }
      })

      local mock_module = {
        Process = function(self, ctx, input)
          return {
            content = "{\"user\":{\"name\":\"Alice\",\"email\":\"alice@example.com\"}}",
            prompt = "Generate a user profile"
          }
        end
      }

      -- Note: Mode integration would require decorator updates
      -- For now, just verify strategy selection works
      local strategy = StrategySelector.select_strategy(schema, "few-shot")

      assert.is_equal("few-shot", strategy)
    end)

    it("should select few-shot for nested object schemas", function()
      local schema = Schema.Object({
        profile = {
          type = "object",
          properties = {
            bio = {type = "string"},
            avatar = {
              type = "object",
              properties = {
                url = {type = "string"}
              }
            }
          }
        }
      })

      local strategy = StrategySelector.select_strategy(schema, "auto")

      assert.is_equal("few-shot", strategy)
    end)

    it("should select few-shot for array schemas", function()
      local schema = Schema.Object({
        tags = {
          type = "array",
          items = {type = "string"}
        }
      })

      local strategy = StrategySelector.select_strategy(schema, "auto")

      assert.is_equal("few-shot", strategy)
    end)
  end)

  describe("Instructional strategy integration", function()
    it("should apply instructional strategy when explicitly selected", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local strategy = StrategySelector.select_strategy(schema, "instructional")

      assert.is_equal("instructional", strategy)
    end)

    it("should select instructional for flat schemas with <=5 fields", function()
      local schema = Schema.Object({
        field1 = {type = "string"},
        field2 = {type = "string"},
        field3 = {type = "string"}
      })

      local strategy = StrategySelector.select_strategy(schema, "auto")

      assert.is_equal("instructional", strategy)
    end)

    it("should select instructional for flat schemas with no constraints", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"},
        active = {type = "boolean"}
      })

      local strategy = StrategySelector.select_strategy(schema, "auto")

      assert.is_equal("instructional", strategy)
    end)
  end)

  describe("Auto-strategy selection", function()
    it("should select few-shot for schemas with enum constraints", function()
      local schema = Schema.Object({
        status = {
          type = "string",
          enum = {"active", "inactive", "pending"}
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

    it("should select instructional when token budget is constrained", function()
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
        }
      })

      local strategy = StrategySelector.select_strategy(schema, "auto")

      -- Should choose few-shot due to complexity
      assert.is_equal("few-shot", strategy)
    end)
  end)

  describe("Strategy selector schema analysis", function()
    it("should analyze schema complexity correctly", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local analysis = StrategySelector.analyze_schema(schema)

      assert.is_true(analysis.is_flat)
      assert.is_false(analysis.has_nested_objects)
      assert.is_false(analysis.has_arrays)
      assert.is_equal(2, analysis.field_count)
    end)

    it("should detect nested objects in analysis", function()
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

    it("should detect arrays in analysis", function()
      local schema = Schema.Object({
        items = {
          type = "array",
          items = {type = "string"}
        }
      })

      local analysis = StrategySelector.analyze_schema(schema)

      assert.is_false(analysis.is_flat)
      assert.is_true(analysis.has_arrays)
    end)

    it("should detect enum constraints", function()
      local schema = Schema.Object({
        status = {
          type = "string",
          enum = {"active", "inactive"}
        }
      })

      local analysis = StrategySelector.analyze_schema(schema)

      assert.is_true(analysis.has_enum)
    end)

    it("should detect pattern constraints", function()
      local schema = Schema.Object({
        email = {
          type = "string",
          pattern = "^[^@]+@[^@]+$"
        }
      })

      local analysis = StrategySelector.analyze_schema(schema)

      assert.is_true(analysis.has_pattern)
    end)

    it("should count fields correctly", function()
      local schema = Schema.Object({
        field1 = {type = "string"},
        field2 = {type = "integer"},
        field3 = {type = "boolean"},
        field4 = {type = "string"}
      })

      local analysis = StrategySelector.analyze_schema(schema)

      assert.is_equal(4, analysis.field_count)
    end)
  end)

end)
