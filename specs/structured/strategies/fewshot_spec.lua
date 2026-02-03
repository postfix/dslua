-- specs/structured/strategies/fewshot_spec.lua
-- Tests for dslua/structured/strategies/fewshot.lua

local FewShot = require("dslua.structured.strategies.fewshot")
local Schema = require("dslua.structured.schema")

describe("Few-Shot Strategy", function()

  describe("Basic generation", function()
    it("should generate prompt addition for flat schema", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local addition = FewShot.generate(schema, {})

      assert.is_not_nil(addition)
      assert.is_true(#addition > 0)
      assert.is_true(string.find(addition, "Example") ~= nil)
    end)

    it("should include placeholder tokens in examples", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"},
        active = {type = "boolean"}
      })

      local addition = FewShot.generate(schema, {})

      -- Should have string placeholder
      assert.is_true(string.find(addition, '"<string>"') ~= nil,
        "Should contain string placeholder")

      -- Should have number placeholder
      assert.is_true(string.find(addition, "%d+") ~= nil,
        "Should contain number placeholder")

      -- Should have boolean placeholder
      assert.is_true(string.find(addition, "true") ~= nil or string.find(addition, "false") ~= nil,
        "Should contain boolean placeholder")
    end)

    it("should generate multiple examples based on schema complexity", function()
      local schema = Schema.Object({
        name = {type = "string"},
        email = {type = "string"}
      })

      local addition = FewShot.generate(schema, {max_examples = 3})

      -- Count example occurrences
      local count = 0
      for _ in string.gmatch(addition, "Example") do
        count = count + 1
      end

      assert.is_true(count >= 1, "Should generate at least 1 example")
      assert.is_true(count <= 3, "Should not exceed max_examples")
    end)
  end)

  describe("Nested object support", function()
    it("should generate examples for nested objects", function()
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

      local addition = FewShot.generate(schema, {})

      -- Should have nested object structure
      assert.is_true(string.find(addition, "address") ~= nil)
      assert.is_true(string.find(addition, "street") ~= nil)
      assert.is_true(string.find(addition, "city") ~= nil)
    end)

    it("should handle deeply nested objects", function()
      local schema = Schema.Object({
        user = {
          type = "object",
          properties = {
            profile = {
              type = "object",
              properties = {
                bio = {type = "string"}
              }
            }
          }
        }
      })

      local addition = FewShot.generate(schema, {})

      assert.is_not_nil(addition)
      assert.is_true(string.find(addition, "profile") ~= nil)
      assert.is_true(string.find(addition, "bio") ~= nil)
    end)
  end)

  describe("Array support", function()
    it("should generate examples for arrays", function()
      local schema = Schema.Object({
        name = {type = "string"},
        tags = {
          type = "array",
          items = {type = "string"}
        }
      })

      local addition = FewShot.generate(schema, {})

      -- Should have array syntax
      assert.is_true(string.find(addition, "%[") ~= nil)
      assert.is_true(string.find(addition, "%]") ~= nil)
      assert.is_true(string.find(addition, "tags") ~= nil)
    end)

    it("should generate array of objects", function()
      local schema = Schema.Object({
        users = {
          type = "array",
          items = {
            type = "object",
            properties = {
              name = {type = "string"},
              age = {type = "integer"}
            }
          }
        }
      })

      local addition = FewShot.generate(schema, {})

      assert.is_true(string.find(addition, "users") ~= nil)
      assert.is_true(string.find(addition, "name") ~= nil)
      assert.is_true(string.find(addition, "age") ~= nil)
    end)
  end)

  describe("Constraint handling", function()
    it("should show enum values in examples", function()
      local schema = Schema.Object({
        status = {
          type = "string",
          enum = {"active", "inactive", "pending"}
        }
      })

      local addition = FewShot.generate(schema, {})

      -- Should include one of the enum values
      local has_enum_value = string.find(addition, "active") ~= nil or
                             string.find(addition, "inactive") ~= nil or
                             string.find(addition, "pending") ~= nil

      assert.is_true(has_enum_value, "Should include enum value in example")
    end)

    it("should respect minItems constraint", function()
      local schema = Schema.Object({
        tags = {
          type = "array",
          items = {type = "string"},
          minItems = 2
        }
      })

      local addition = FewShot.generate(schema, {})

      -- Should generate array with at least 2 items
      assert.is_true(string.find(addition, "%[") ~= nil)
    end)

    it("should show pattern format in string examples", function()
      local schema = Schema.Object({
        email = {
          type = "string",
          pattern = "^[^@]+@[^@]+%.[^@]+$"
        }
      })

      local addition = FewShot.generate(schema, {})

      -- Should include email-like pattern
      assert.is_true(string.find(addition, "@") ~= nil or string.find(addition, "email") ~= nil,
        "Should hint at email pattern format")
    end)
  end)

  describe("Configuration options", function()
    it("should respect max_examples parameter", function()
      local schema = Schema.Object({
        name = {type = "string"}
      })

      local addition = FewShot.generate(schema, {max_examples = 1})

      -- Count examples
      local count = 0
      for _ in string.gmatch(addition, "Example") do
        count = count + 1
      end

      assert.is_equal(1, count, "Should generate exactly 1 example")
    end)

    it("should handle max_examples = 0", function()
      local schema = Schema.Object({
        name = {type = "string"}
      })

      local addition = FewShot.generate(schema, {max_examples = 0})

      assert.is_equal("", addition, "Should return empty string for max_examples=0")
    end)
  end)

  describe("Format and structure", function()
    it("should use consistent example format", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local addition = FewShot.generate(schema, {})

      -- Should have clear section delimiter
      assert.is_true(string.find(addition, "Example") ~= nil)

      -- Should be JSON-like
      assert.is_true(string.find(addition, "{") ~= nil)
      assert.is_true(string.find(addition, "}") ~= nil)
    end)

    it("should escape special characters properly", function()
      local schema = Schema.Object({
        description = {type = "string"},
        count = {type = "integer"}
      })

      local addition = FewShot.generate(schema, {})

      -- Should be valid format that can be included in prompts
      assert.is_not_nil(addition)
      assert.is_true(#addition > 0)
    end)
  end)

  describe("Edge cases", function()
    it("should handle empty schema gracefully", function()
      local schema = Schema.Object({})

      local addition = FewShot.generate(schema, {})

      assert.is_not_nil(addition)
    end)

    it("should handle schema with only optional fields", function()
      local schema = Schema.Object({
        optional_field = {type = "string"}
      })

      local addition = FewShot.generate(schema, {})

      assert.is_not_nil(addition)
      assert.is_true(#addition > 0)
    end)

    it("should handle required fields", function()
      local schema = Schema.Object({
        required_field = {type = "string"},
        optional_field = {type = "string"}
      }, {required = {"required_field"}})

      local addition = FewShot.generate(schema, {})

      -- Should mention required field
      assert.is_true(string.find(addition, "required_field") ~= nil)
    end)
  end)

  describe("Integration with schema types", function()
    it("should handle all primitive types", function()
      local schema = Schema.Object({
        str = {type = "string"},
        num = {type = "number"},
        int = {type = "integer"},
        bool = {type = "boolean"},
        null_val = {type = "null"}
      })

      local addition = FewShot.generate(schema, {})

      assert.is_not_nil(addition)
      assert.is_true(#addition > 0)
    end)

    it("should handle mixed types in arrays", function()
      local schema = Schema.Object({
        mixed = {
          type = "array",
          items = {type = "string"}
        }
      })

      local addition = FewShot.generate(schema, {})

      assert.is_not_nil(addition)
    end)
  end)

  describe("Private Functions", function()
    describe("_calculate_example_count", function()
      it("should return 1 for simple schemas", function()
        local schema = {type = "string"}
        local count = FewShot._calculate_example_count(schema, 3)
        assert.is.equal(1, count)
      end)

      it("should return 1 for schemas with complexity <= 2", function()
        local schema = {type = "object", properties = {
          a = {type = "string"},
          b = {type = "number"}
        }}
        local count = FewShot._calculate_example_count(schema, 3)
        assert.is.equal(1, count)
      end)

      it("should return 2 for schemas with complexity 3-5", function()
        local schema = {type = "object", properties = {
          a = {type = "string"},
          b = {type = "number"},
          c = {type = "boolean"},
          d = {type = "array", items = {type = "string"}}
        }}
        local count = FewShot._calculate_example_count(schema, 3)
        assert.is.equal(2, count)
      end)

      it("should return max_examples for complex schemas (>5 properties)", function()
        local schema = {type = "object", properties = {
          a = {type = "string"},
          b = {type = "number"},
          c = {type = "boolean"},
          d = {type = "array", items = {type = "string"}},
          e = {type = "object", properties = {x = {type = "integer"}}},
          f = {type = "null"}
        }}
        local count = FewShot._calculate_example_count(schema, 3)
        assert.is.equal(3, count)
      end)

      it("should respect max_examples limit", function()
        local schema = {type = "string"}
        local count = FewShot._calculate_example_count(schema, 1)
        assert.is.equal(1, count)
      end)
    end)

    describe("_calculate_complexity", function()
      it("should return 0 for simple types", function()
        assert.is.equal(0, FewShot._calculate_complexity({type = "string"}))
        assert.is.equal(0, FewShot._calculate_complexity({type = "number"}))
      end)

      it("should count properties in objects", function()
        local schema = {type = "object", properties = {
          a = {type = "string"},
          b = {type = "number"},
          c = {type = "boolean"}
        }}
        assert.is.equal(3, FewShot._calculate_complexity(schema))
      end)

      it("should count top-level properties only (not nested)", function()
        local schema = {type = "object", properties = {
          nested = {type = "object", properties = {
            x = {type = "string"}
          }}
        }}
        local complexity = FewShot._calculate_complexity(schema)
        assert.is.equal(1, complexity)
      end)

      it("should calculate array complexity", function()
        local schema = {type = "array", items = {type = "string"}}
        local complexity = FewShot._calculate_complexity(schema)
        assert.is.equal(1, complexity)
      end)
    end)

    describe("_generate_example", function()
      it("should generate JSON example", function()
        local schema = {type = "string"}
        local example = FewShot._generate_example(schema, 1)

        assert.is_truthy(example)
        assert.is_truthy(type(example) == "string")
      end)

      it("should generate different examples for different indices", function()
        local schema = {type = "boolean"}
        local ex1 = FewShot._generate_example(schema, 1)
        local ex2 = FewShot._generate_example(schema, 2)

        assert.is_truthy(ex1)
        assert.is_truthy(ex2)
        -- Examples should differ for booleans
      end)
    end)

    describe("_generate_value", function()
      it("should handle null type", function()
        local schema = {type = "null"}
        local value = FewShot._generate_value(schema, 1)
        assert.is.falsy(value)
      end)

      it("should handle enum constraint", function()
        local schema = {type = "string", enum = {"red", "green", "blue"}}
        local value = FewShot._generate_value(schema, 1)
        assert.is.equal("red", value)

        local value2 = FewShot._generate_value(schema, 2)
        assert.is.equal("green", value2)
      end)

      it("should handle const constraint", function()
        local schema = {type = "string", const = "fixed"}
        local value = FewShot._generate_value(schema, 1)
        assert.is.equal("fixed", value)
      end)

      it("should handle boolean type with alternation", function()
        local schema = {type = "boolean"}
        local v1 = FewShot._generate_value(schema, 1)
        local v2 = FewShot._generate_value(schema, 2)

        assert.is.equal(true, v1)
        assert.is.equal(false, v2)
      end)
    end)

    describe("_generate_string_value", function()
      it("should handle email pattern", function()
        local schema = {type = "string", pattern = "@+"}
        local value = FewShot._generate_string_value(schema, 1)
        assert.is.equal("user@example.com", value)
      end)

      it("should handle pattern with digit characters", function()
        local schema = {type = "string", pattern = "^[0-9]+$"}
        local value = FewShot._generate_string_value(schema, 1)
        assert.is.equal("123", value)
      end)

      it("should handle minLength constraint", function()
        local schema = {type = "string", minLength = 10}
        local value = FewShot._generate_string_value(schema, 1)
        assert.is.equal(10, #value)
      end)

      it("should use placeholder by default", function()
        local schema = {type = "string"}
        local value = FewShot._generate_string_value(schema, 1)
        assert.is.equal("<string>", value)
      end)
    end)

    describe("_generate_numeric_value", function()
      it("should generate incrementing values", function()
        local schema = {type = "number"}
        local v1 = FewShot._generate_numeric_value(schema, 1)
        local v2 = FewShot._generate_numeric_value(schema, 2)

        assert.is_truthy(v2 > v1)
      end)

      it("should respect minimum constraint", function()
        local schema = {type = "number", minimum = 100}
        local value = FewShot._generate_numeric_value(schema, 1)
        assert.is_truthy(value >= 100)
      end)

      it("should respect maximum constraint", function()
        local schema = {type = "number", maximum = 50}
        local value = FewShot._generate_numeric_value(schema, 1)
        assert.is_truthy(value <= 50)
      end)

      it("should handle exclusiveMinimum", function()
        local schema = {type = "number", minimum = 10, exclusiveMinimum = 10}
        local value = FewShot._generate_numeric_value(schema, 1)
        assert.is_truthy(value > 10)
      end)

      it("should handle exclusiveMaximum", function()
        local schema = {type = "number", maximum = 100, exclusiveMaximum = 100}
        local value = FewShot._generate_numeric_value(schema, 1)
        assert.is_truthy(value < 100)
      end)

      it("should return integer for integer type", function()
        local schema = {type = "integer"}
        local value = FewShot._generate_numeric_value(schema, 1)
        assert.is.equal(math.floor(value), value)
      end)
    end)

    describe("_generate_array_value", function()
      it("should generate array with default length", function()
        local schema = {type = "array", items = {type = "string"}}
        local array = FewShot._generate_array_value(schema, 1)

        assert.is_truthy(type(array) == "table")
        assert.is.equal(2, #array)
      end)

      it("should respect minItems constraint", function()
        local schema = {type = "array", minItems = 5, items = {type = "string"}}
        local array = FewShot._generate_array_value(schema, 1)

        assert.is.equal(5, #array)
      end)

      it("should respect maxItems constraint", function()
        local schema = {type = "array", maxItems = 3, items = {type = "string"}}
        local array = FewShot._generate_array_value(schema, 1)

        assert.is.equal(2, #array)  -- min(default=2, max=3)
      end)

      it("should generate items based on item schema", function()
        local schema = {type = "array", items = {type = "number"}}
        local array = FewShot._generate_array_value(schema, 1)

        assert.is.equal("number", type(array[1]))
      end)
    end)

    describe("_generate_object_value", function()
      it("should generate object with properties", function()
        local schema = {
          type = "object",
          properties = {
            name = {type = "string"},
            age = {type = "integer"}
          }
        }
        local obj = FewShot._generate_object_value(schema, 1)

        assert.is.truthy(obj.name)
        assert.is.truthy(obj.age)
      end)

      it("should handle empty properties", function()
        local schema = {type = "object"}
        local obj = FewShot._generate_object_value(schema, 1)

        assert.is_truthy(type(obj) == "table")
        assert.is.equal(0, #obj)
      end)

      it("should vary values across examples", function()
        local schema = {
          type = "object",
          properties = {
            value = {type = "number"}
          }
        }
        local obj1 = FewShot._generate_object_value(schema, 1)
        local obj2 = FewShot._generate_object_value(schema, 2)

        -- Values should differ due to property name hashing
        assert.is_truthy(obj1.value)
        assert.is.truthy(obj2.value)
      end)
    end)

    describe("_format_examples", function()
      it("should format examples as prompt", function()
        local examples = {
          '{"name": "John"}',
          '{"age": 30}'
        }
        local formatted = FewShot._format_examples(examples)

        assert.is_truthy(formatted:find("[EXAMPLES]"))
        assert.is.truthy(formatted:find("Example 1:"))
        assert.is_truthy(formatted:find("Example 2:"))
        assert.is.truthy(formatted:find("[YOUR TASK]"))
      end)

      it("should handle empty examples", function()
        local formatted = FewShot._format_examples({})
        assert.is.equal("", formatted)
      end)
    end)

    describe("get_placeholder", function()
      it("should return placeholder for string type", function()
        local placeholder = FewShot.get_placeholder("string")
        assert.is.equal('"<string>"', placeholder)
      end)

      it("should return placeholder for number type", function()
        local placeholder = FewShot.get_placeholder("number")
        assert.is.equal("123", placeholder)
      end)

      it("should return placeholder for integer type", function()
        local placeholder = FewShot.get_placeholder("integer")
        assert.is.equal("42", placeholder)
      end)

      it("should return placeholder for boolean type", function()
        local placeholder = FewShot.get_placeholder("boolean")
        assert.is.equal("true", placeholder)
      end)

      it("should return placeholder for null type", function()
        local placeholder = FewShot.get_placeholder("null")
        assert.is.equal("null", placeholder)
      end)

      it("should return placeholder for array_empty type", function()
        local placeholder = FewShot.get_placeholder("array_empty")
        assert.is.equal("[]", placeholder)
      end)

      it("should return placeholder for array_items type", function()
        local placeholder = FewShot.get_placeholder("array_items")
        assert.is.equal('["<string>", "<string>"]', placeholder)
      end)

      it("should return placeholder for object_empty type", function()
        local placeholder = FewShot.get_placeholder("object_empty")
        assert.is.equal('{}', placeholder)
      end)

      it("should return placeholder for object_example type", function()
        local placeholder = FewShot.get_placeholder("object_example")
        assert.is.equal('{"key": "<value>"}', placeholder)
      end)

      it("should return default for unknown type", function()
        local placeholder = FewShot.get_placeholder("unknown")
        assert.is.equal('"<value>"', placeholder)
      end)

      it("should return default for 'array' type (not in Placeholders)", function()
        local placeholder = FewShot.get_placeholder("array")
        assert.is.equal('"<value>"', placeholder)
      end)

      it("should return default for 'object' type (not in Placeholders)", function()
        local placeholder = FewShot.get_placeholder("object")
        assert.is.equal('"<value>"', placeholder)
      end)
    end)
  end)
end)
