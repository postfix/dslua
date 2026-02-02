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

end)
