-- specs/structured/validator_spec.lua
-- Tests for dslua/structured/validator.lua

local Validator = require("dslua.structured.validator")
local Schema = require("dslua.structured.schema")

describe("Validator Module", function()

  describe("Primitive type validation", function()
    it("should validate string type", function()
      local schema = Schema.String()
      local result = Validator.validate("hello", schema)

      assert.is_true(result.ok)
      assert.is_equal(0, #result.errors)
    end)

    it("should reject non-string", function()
      local schema = Schema.String()
      local result = Validator.validate(123, schema)

      assert.is_false(result.ok)
      assert.is_equal(1, #result.errors)
      assert.is.equal("/type", result.errors[1].path)
      assert.is.equal("type", result.errors[1].keyword)
      assert.is.equal("string", result.errors[1].expected)
      assert.is.equal("number", result.errors[1].actual)
    end)

    it("should validate number type", function()
      local schema = Schema.Number()
      local result = Validator.validate(42, schema)

      assert.is_true(result.ok)
    end)

    it("should validate integer type", function()
      local schema = Schema.Integer()
      local result = Validator.validate(42, schema)

      assert.is_true(result.ok)
    end)

    it("should accept 1.0 as integer", function()
      local schema = Schema.Integer()
      local result = Validator.validate(1.0, schema)

      assert.is_true(result.ok)
    end)

    it("should validate boolean type", function()
      local schema = Schema.Boolean()
      local result = Validator.validate(true, schema)

      assert.is_true(result.ok)
    end)

    it("should validate null type", function()
      local schema = Schema.Null()
      local result = Validator.validate(nil, schema)

      assert.is_true(result.ok)
    end)
  end)

  describe("String constraint validation", function()
    it("should validate minLength", function()
      local schema = Schema.String({minLength = 3})
      local result = Validator.validate("hi", schema)

      assert.is_false(result.ok)
      assert.is_equal("/minLength", result.errors[1].path)
    end)

    it("should validate maxLength", function()
      local schema = Schema.String({maxLength = 5})
      local result = Validator.validate("hello world", schema)

      assert.is_false(result.ok)
      assert.is_equal("/maxLength", result.errors[1].path)
    end)

    it("should validate pattern constraint", function()
      local schema = Schema.String({pattern = "^[a-z]+$"})
      local result = Validator.validate("ABC123", schema)

      assert.is_false(result.ok)
      assert.is_equal("/pattern", result.errors[1].path)
    end)
  end)

  describe("Numeric constraint validation", function()
    it("should validate minimum", function()
      local schema = Schema.Number({minimum = 10})
      local result = Validator.validate(5, schema)

      assert.is_false(result.ok)
      assert.is_equal("/minimum", result.errors[1].path)
    end)

    it("should validate maximum", function()
      local schema = Schema.Number({maximum = 100})
      local result = Validator.validate(150, schema)

      assert.is_false(result.ok)
      assert.is_equal("/maximum", result.errors[1].path)
    end)

    it("should validate exclusiveMinimum", function()
      local schema = Schema.Number({minimum = 10, exclusiveMinimum = true})
      local result = Validator.validate(10, schema)

      assert.is_false(result.ok)
      assert.is_equal("/minimum", result.errors[1].path)
    end)

    it("should validate exclusiveMaximum", function()
      local schema = Schema.Number({maximum = 100, exclusiveMaximum = true})
      local result = Validator.validate(100, schema)

      assert.is_false(result.ok)
      assert.is_equal("/maximum", result.errors[1].path)
    end)
  end)

  describe("Object validation", function()
    it("should validate object structure", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "number"}
      })

      local data = {name = "Alice", age = 30}
      local result = Validator.validate(data, schema)

      assert.is_true(result.ok)
    end)

    it("should enforce required fields", function()
      local schema = Schema.Object({
        name = {type = "string"}
      }, {required = {"name"}})

      local data = {}  -- Missing name
      local result = Validator.validate(data, schema)

      assert.is_false(result.ok)
      assert.is_equal("/name", result.errors[1].path)
      assert.is.equal("required", result.errors[1].keyword)
    end)

    it("should validate property types", function()
      local schema = Schema.Object({
        age = {type = "number"}
      })

      local data = {age = "30"}  -- String, not number
      local result = Validator.validate(data, schema)

      assert.is_false(result.ok)
      assert.is_equal("/age/type", result.errors[1].path)
    end)

    it("should enforce additionalProperties=false", function()
      local schema = Schema.Object({
        name = {type = "string"}
      }, {additionalProperties = false})

      local data = {name = "Alice", extra = "field"}  -- Extra field
      local result = Validator.validate(data, schema)

      assert.is_false(result.ok)
      assert.is_equal("/additionalProperties", result.errors[1].path)
    end)
  end)

  describe("Array validation", function()
    it("should validate array structure", function()
      local schema = Schema.Array({type = "number"})
      local data = {1, 2, 3, 4, 5}

      local result = Validator.validate(data, schema)

      assert.is_true(result.ok)
    end)

    it("should validate item types", function()
      local schema = Schema.Array({type = "string"})
      local data = {"hello", 42, "world"}  -- 42 is not string

      local result = Validator.validate(data, schema)

      assert.is_false(result.ok)
      assert.is_equal("/1/type", result.errors[1].path)
    end)

    it("should validate minItems", function()
      local schema = Schema.Array({type = "string"}, {minItems = 2})
      local data = {"one"}

      local result = Validator.validate(data, schema)

      assert.is_false(result.ok)
      assert.is_equal("/minItems", result.errors[1].path)
    end)

    it("should validate maxItems", function()
      local schema = Schema.Array({type = "string"}, {maxItems = 2})
      local data = {"one", "two", "three"}

      local result = Validator.validate(data, schema)

      assert.is_false(result.ok)
      assert.is_equal("/maxItems", result.errors[1].path)
    end)
  end)

  describe("Enum validation", function()
    it("should validate enum values", function()
      local schema = Schema.Enum({"red", "green", "blue"})
      local result = Validator.validate("yellow", schema)

      assert.is_false(result.ok)
      assert.is_equal("/enum", result.errors[1].path)
    end)

    it("should accept valid enum value", function()
      local schema = Schema.Enum({"red", "green", "blue"})
      local result = Validator.validate("green", schema)

      assert.is_true(result.ok)
    end)
  end)

  describe("Const validation", function()
    it("should validate const value", function()
      local schema = Schema.Const("fixed")
      local result = Validator.validate("different", schema)

      assert.is_false(result.ok)
      assert.is_equal("/const", result.errors[1].path)
    end)
  end)

  describe("Composition validation", function()
    it("should validate oneOf - exactly one must match", function()
      local schema = Schema.OneOf({
        {type = "string"},
        {type = "number"}
      })

      -- Both match (string "42" can be number too in Lua)
      local data = "42"
      local result = Validator.validate(data, schema)

      -- Should fail because more than one matches
      -- Note: In Lua, "42" is a string, not number, so only one matches
      -- This test depends on Lua's type system
      assert.is_true(result.ok)  -- String matches
    end)

    it("should validate allOf - all must match", function()
      local schema = Schema.AllOf({
        {type = "string"},
        {minLength = 5}
      })

      local data = "hi"  -- Type matches but minLength fails
      local result = Validator.validate(data, schema)

      assert.is_false(result.ok)
    end)
  end)

  describe("Custom validator registration", function()
    it("should allow registering custom validators", function()
      -- Register a custom keyword validator
      Validator.register("x-min-length", function(value, schema)
        local min_len = schema["x-min-length"]
        if type(value) == "string" and #value < min_len then
          return false, {
            path = "/x-min-length",
            keyword = "x-min-length",
            expected = "length >= " .. min_len,
            actual = "length = " .. #value
          }
        end
        return true
      end)

      local schema = {
        type = "string",
        ["x-min-length"] = 10
      }

      local data = "short"
      local result = Validator.validate(data, schema)

      assert.is_false(result.ok)
      assert.is_equal("/x-min-length", result.errors[1].path)
    end)
  end)
end)
