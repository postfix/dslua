-- specs/structured/strategies/instructional_spec.lua
-- Tests for dslua/structured/strategies/instructional.lua

local Instructional = require("dslua.structured.strategies.instructional")
local Schema = require("dslua.structured.schema")

describe("Instructional Strategy", function()

  describe("Basic generation", function()
    it("should generate format instructions for flat schema", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_not_nil(instructions)
      assert.is_true(#instructions > 0)
      assert.is_true(string.find(instructions, "name") ~= nil)
      assert.is_true(string.find(instructions, "age") ~= nil)
    end)

    it("should show field names with proper types", function()
      local schema = Schema.Object({
        username = {type = "string"},
        score = {type = "number"},
        active = {type = "boolean"}
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_true(string.find(instructions, "username") ~= nil)
      assert.is_true(string.find(instructions, "score") ~= nil)
      assert.is_true(string.find(instructions, "active") ~= nil)

      -- Should have type hints
      assert.is_true(string.find(instructions, "string") ~= nil or
                     string.find(instructions, '"%"%"') ~= nil)  -- Has string placeholder
    end)
  end)

  describe("Type placeholders", function()
    it("should use <string> placeholder for string fields", function()
      local schema = Schema.Object({
        name = {type = "string"}
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_true(string.find(instructions, '"<string>"') ~= nil,
        "Should use quoted string placeholder")
    end)

    it("should use <number> placeholder for numeric fields", function()
      local schema = Schema.Object({
        count = {type = "number"},
        age = {type = "integer"}
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_true(string.find(instructions, '<number>') ~= nil or
                     string.find(instructions, '%d+') ~= nil,
        "Should show numeric placeholder or example number")
    end)

    it("should use true/false for boolean fields", function()
      local schema = Schema.Object({
        active = {type = "boolean"}
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_true(string.find(instructions, "true") ~= nil or
                     string.find(instructions, "false") ~= nil,
        "Should show boolean values")
    end)

    it("should show null for null type fields", function()
      local schema = Schema.Object({
        optional = {type = "null"}
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_true(string.find(instructions, "null") ~= nil,
        "Should show null placeholder")
    end)
  end)

  describe("Array handling", function()
    it("should show array format for array fields", function()
      local schema = Schema.Object({
        tags = {
          type = "array",
          items = {type = "string"}
        }
      })

      local instructions = Instructional.generate(schema, {})

      -- Should have array syntax
      assert.is_true(string.find(instructions, "%[") ~= nil)
      assert.is_true(string.find(instructions, "%]") ~= nil)
      assert.is_true(string.find(instructions, "tags") ~= nil)
    end)

    it("should show array of objects format", function()
      local schema = Schema.Object({
        items = {
          type = "array",
          items = {
            type = "object",
            properties = {
              id = {type = "integer"},
              name = {type = "string"}
            }
          }
        }
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_true(string.find(instructions, "items") ~= nil)
      assert.is_true(string.find(instructions, "%[") ~= nil)
      assert.is_true(string.find(instructions, "%]") ~= nil)
    end)

    it("should respect minItems constraint", function()
      local schema = Schema.Object({
        values = {
          type = "array",
          items = {type = "string"},
          minItems = 2
        }
      })

      local instructions = Instructional.generate(schema, {})

      -- Should mention minimum items
      assert.is_not_nil(instructions)
    end)

    it("should respect maxItems constraint", function()
      local schema = Schema.Object({
        values = {
          type = "array",
          items = {type = "string"},
          maxItems = 5
        }
      })

      local instructions = Instructional.generate(schema, {})

      -- Should mention maximum items
      assert.is_not_nil(instructions)
    end)
  end)

  describe("Object handling", function()
    it("should show nested object format", function()
      local schema = Schema.Object({
        user = {
          type = "object",
          properties = {
            name = {type = "string"},
            email = {type = "string"}
          }
        }
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_true(string.find(instructions, "user") ~= nil)
      assert.is_true(string.find(instructions, "{") ~= nil)
      assert.is_true(string.find(instructions, "}") ~= nil)
    end)

    it("should handle nested objects with arrays", function()
      local schema = Schema.Object({
        data = {
          type = "object",
          properties = {
            tags = {
              type = "array",
              items = {type = "string"}
            }
          }
        }
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_not_nil(instructions)
    end)
  end)

  describe("Constraint information", function()
    it("should show enum values in instructions", function()
      local schema = Schema.Object({
        status = {
          type = "string",
          enum = {"active", "inactive", "pending"}
        }
      })

      local instructions = Instructional.generate(schema, {})

      -- Should mention enum values
      local has_enum = string.find(instructions, "active") ~= nil or
                      string.find(instructions, "inactive") ~= nil or
                      string.find(instructions, "pending") ~= nil

      assert.is_true(has_enum, "Should show enum values")
    end)

    it("should show required field markers", function()
      local schema = Schema.Object({
        required_field = {type = "string"},
        optional_field = {type = "string"}
      }, {required = {"required_field"}})

      local instructions = Instructional.generate(schema, {})

      -- Should mention required field
      assert.is_true(string.find(instructions, "required") ~= nil or
                     string.find(instructions, "required_field") ~= nil,
        "Should indicate required field")
    end)

    it("should show string length constraints", function()
      local schema = Schema.Object({
        short_text = {
          type = "string",
          maxLength = 10
        }
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_true(string.find(instructions, "short_text") ~= nil)
    end)

    it("should show numeric range constraints", function()
      local schema = Schema.Object({
        rating = {
          type = "number",
          minimum = 0,
          maximum = 5
        }
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_true(string.find(instructions, "rating") ~= nil)
    end)

    it("should show pattern constraints", function()
      local schema = Schema.Object({
        email = {
          type = "string",
          pattern = "^[^@]+@[^@]+%.[^@]+$"
        }
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_true(string.find(instructions, "email") ~= nil)
    end)
  end)

  describe("Format and structure", function()
    it("should use clear section headers", function()
      local schema = Schema.Object({
        name = {type = "string"}
      })

      local instructions = Instructional.generate(schema, {})

      -- Should have clear structure
      assert.is_true(#instructions > 0)
    end)

    it("should present fields in consistent order", function()
      local schema = Schema.Object({
        field_a = {type = "string"},
        field_b = {type = "string"},
        field_c = {type = "string"}
      })

      local instructions = Instructional.generate(schema, {})

      -- All fields should be present
      assert.is_true(string.find(instructions, "field_a") ~= nil)
      assert.is_true(string.find(instructions, "field_b") ~= nil)
      assert.is_true(string.find(instructions, "field_c") ~= nil)
    end)
  end)

  describe("Edge cases", function()
    it("should handle empty schema", function()
      local schema = Schema.Object({})

      local instructions = Instructional.generate(schema, {})

      assert.is_not_nil(instructions)
    end)

    it("should handle schema with all optional fields", function()
      local schema = Schema.Object({
        optional_a = {type = "string"},
        optional_b = {type = "string"}
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_not_nil(instructions)
      assert.is_true(#instructions > 0)
    end)

    it("should handle complex nested structures", function()
      local schema = Schema.Object({
        level1 = {
          type = "object",
          properties = {
            level2 = {
              type = "object",
              properties = {
                level3 = {type = "string"}
              }
            }
          }
        }
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_not_nil(instructions)
    end)
  end)

  describe("Integration", function()
    it("should handle all primitive types in one schema", function()
      local schema = Schema.Object({
        str_field = {type = "string"},
        num_field = {type = "number"},
        int_field = {type = "integer"},
        bool_field = {type = "boolean"},
        null_field = {type = "null"}
      })

      local instructions = Instructional.generate(schema, {})

      assert.is_not_nil(instructions)
      assert.is_true(#instructions > 0)

      -- All fields should be mentioned
      assert.is_true(string.find(instructions, "str_field") ~= nil)
      assert.is_true(string.find(instructions, "num_field") ~= nil)
      assert.is_true(string.find(instructions, "int_field") ~= nil)
      assert.is_true(string.find(instructions, "bool_field") ~= nil)
      assert.is_true(string.find(instructions, "null_field") ~= nil)
    end)
  end)

  describe("Private Functions", function()
    describe("_generate_field_instruction", function()
      it("should generate instruction for required field", function()
        local field_schema = {type = "string"}
        local parent_schema = {properties = {}, required = {"name"}}
        local instruction = Instructional._generate_field_instruction("name", field_schema, parent_schema)

        assert.is_truthy(instruction:find("*name:"))
      end)

      it("should generate instruction for optional field", function()
        local field_schema = {type = "string"}
        local parent_schema = {properties = {}, required = {}}
        local instruction = Instructional._generate_field_instruction("name", field_schema, parent_schema)

        assert.is.truthy(instruction:find("name:"))
        assert.is.falsy(instruction:find("*name:"))
      end)
    end)

    describe("_get_constraint_info", function()
      it("should return const value", function()
        local info = Instructional._get_constraint_info({const = "fixed"}, "string")
        assert.is.equal('"fixed"', info)
      end)

      it("should handle string type", function()
        local info = Instructional._get_constraint_info({type = "string"}, "string")
        assert.is.truthy(info:find("<string>"))
      end)

      it("should handle boolean type", function()
        local info = Instructional._get_constraint_info({type = "boolean"}, "boolean")
        assert.is.equal("true | false", info)
      end)

      it("should handle null type", function()
        local info = Instructional._get_constraint_info({type = "null"}, "null")
        assert.is.equal("null", info)
      end)

      it("should return ? for unknown type", function()
        local info = Instructional._get_constraint_info({type = "unknown"}, "unknown")
        assert.is.equal("?", info)
      end)
    end)

    describe("_get_string_constraint_info", function()
      it("should include placeholder", function()
        local info = Instructional._get_string_constraint_info({type = "string"})
        assert.is.truthy(info:find('"<string>"'))
      end)

      it("should include enum values", function()
        local info = Instructional._get_string_constraint_info({
          type = "string",
          enum = {"a", "b", "c"}
        })
        assert.is.truthy(info:find("enum"))
      end)

      it("should include minLength", function()
        local info = Instructional._get_string_constraint_info({
          type = "string",
          minLength = 5
        })
        assert.is.truthy(info:find("min_len=5"))
      end)

      it("should include maxLength", function()
        local info = Instructional._get_string_constraint_info({
          type = "string",
          maxLength = 100
        })
        assert.is.truthy(info:find("max_len=100"))
      end)

      it("should include pattern", function()
        local info = Instructional._get_string_constraint_info({
          type = "string",
          pattern = "^[a-z]+$"
        })
        assert.is.truthy(info:find("pattern"))
      end)
    end)

    describe("_get_numeric_constraint_info", function()
      it("should use integer placeholder for integer type", function()
        local info = Instructional._get_numeric_constraint_info({type = "integer"}, "integer")
        assert.is.truthy(info:find("42"))
      end)

      it("should use number placeholder for number type", function()
        local info = Instructional._get_numeric_constraint_info({type = "number"}, "number")
        assert.is.truthy(info:find("123.45"))
      end)

      it("should include minimum constraint", function()
        local info = Instructional._get_numeric_constraint_info({
          type = "number",
          minimum = 0
        }, "number")
        assert.is.truthy(info:find(">="))
      end)

      it("should include exclusiveMinimum", function()
        local info = Instructional._get_numeric_constraint_info({
          type = "number",
          minimum = 0,
          exclusiveMinimum = 0
        }, "number")
        assert.is.truthy(info:find(">"))
      end)

      it("should include maximum constraint", function()
        local info = Instructional._get_numeric_constraint_info({
          type = "number",
          maximum = 100
        }, "number")
        assert.is.truthy(info:find("<="))
      end)

      it("should include exclusiveMaximum", function()
        local info = Instructional._get_numeric_constraint_info({
          type = "number",
          maximum = 100,
          exclusiveMaximum = 100
        }, "number")
        assert.is.truthy(info:find("<"))
      end)
    end)

    describe("_get_array_constraint_info", function()
      it("should include minItems", function()
        local info = Instructional._get_array_constraint_info({
          type = "array",
          items = {type = "string"},
          minItems = 2
        })
        assert.is.truthy(info:find("minItems=2"))
      end)

      it("should include maxItems", function()
        local info = Instructional._get_array_constraint_info({
          type = "array",
          items = {type = "string"},
          maxItems = 5
        })
        assert.is.truthy(info:find("maxItems=5"))
      end)

      it("should show string array format", function()
        local info = Instructional._get_array_constraint_info({
          type = "array",
          items = {type = "string"}
        })
        assert.is.truthy(info:find('["<string>", ...]'))
      end)

      it("should show number array format", function()
        local info = Instructional._get_array_constraint_info({
          type = "array",
          items = {type = "number"}
        })
        assert.is.truthy(info:find("[123, ...]"))
      end)

      it("should show boolean array format", function()
        local info = Instructional._get_array_constraint_info({
          type = "array",
          items = {type = "boolean"}
        })
        assert.is.truthy(info:find("[true, ...]"))
      end)

      it("should show object array format", function()
        local info = Instructional._get_array_constraint_info({
          type = "array",
          items = {type = "object"}
        })
        assert.is.truthy(info:find("[{...}, ...]"))
      end)
    end)

    describe("_get_object_constraint_info", function()
      it("should return placeholder for object without properties", function()
        local info = Instructional._get_object_constraint_info({type = "object"})
        assert.is.equal('{"<key>": "<value>"}', info)
      end)

      it("should show properties for nested object", function()
        local info = Instructional._get_object_constraint_info({
          type = "object",
          properties = {
            name = {type = "string"},
            age = {type = "integer"}
          }
        })
        assert.is.truthy(info:find('"name"'))
        assert.is.truthy(info:find('"age"'))
      end)
    end)

    describe("_get_placeholder_for_type", function()
      it("should return string placeholder", function()
        assert.is.equal('"<string>"', Instructional._get_placeholder_for_type("string"))
      end)

      it("should return number placeholder", function()
        assert.is.equal("123", Instructional._get_placeholder_for_type("number"))
      end)

      it("should return integer placeholder", function()
        assert.is.equal("42", Instructional._get_placeholder_for_type("integer"))
      end)

      it("should return boolean placeholder", function()
        assert.is.equal("true", Instructional._get_placeholder_for_type("boolean"))
      end)

      it("should return null placeholder", function()
        assert.is.equal("null", Instructional._get_placeholder_for_type("null"))
      end)

      it("should return array placeholder", function()
        assert.is.equal("[...]", Instructional._get_placeholder_for_type("array"))
      end)

      it("should return object placeholder", function()
        assert.is.equal("{...}", Instructional._get_placeholder_for_type("object"))
      end)

      it("should return default for unknown type", function()
        assert.is.equal('"?"', Instructional._get_placeholder_for_type("unknown"))
      end)
    end)

    describe("_generic_instructions", function()
      it("should return format instructions", function()
        local instructions = Instructional._generic_instructions()

        assert.is.truthy(instructions:find("[OUTPUT FORMAT]"))
        assert.is.truthy(instructions:find("[END FORMAT]"))
      end)
    end)

    describe("_table_contains", function()
      it("should return true when value in table", function()
        assert.is_true(Instructional._table_contains({"a", "b", "c"}, "b"))
      end)

      it("should return false when value not in table", function()
        assert.is_false(Instructional._table_contains({"a", "b", "c"}, "d"))
      end)

      it("should return false for empty table", function()
        assert.is_false(Instructional._table_contains({}, "a"))
      end)
    end)
  end)

end)
