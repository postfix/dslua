-- specs/structured/schema_spec.lua
-- Tests for dslua/structured/schema.lua

local Schema = require("dslua.structured.schema")

describe("Schema Module", function()

  describe("Object builder", function()
    it("should create an object schema", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "number"}
      })

      assert.is_not_nil(schema)
      assert.is.equal("object", schema.type)
      assert.is_not_nil(schema.properties)
      assert.is.equal("string", schema.properties.name.type)
      assert.is.equal("number", schema.properties.age.type)
    end)

    it("should support required fields", function()
      local schema = Schema.Object(
        {name = {type = "string"}},
        {required = {"name"}}
      )

      assert.is.same({"name"}, schema.required)
    end)

    it("should support additionalProperties", function()
      local schema = Schema.Object(
        {name = {type = "string"}},
        {additionalProperties = false}
      )

      assert.is_false(schema.additionalProperties)
    end)
  end)

  describe("Array builder", function()
    it("should create an array schema", function()
      local schema = Schema.Array({type = "string"})

      assert.is.equal("array", schema.type)
      assert.is_not_nil(schema.items)
      assert.is.equal("string", schema.items.type)
    end)

    it("should support minItems and maxItems", function()
      local schema = Schema.Array(
        {type = "number"},
        {minItems = 1, maxItems = 10}
      )

      assert.is.equal(1, schema.minItems)
      assert.is.equal(10, schema.maxItems)
    end)
  end)

  describe("Primitive builders", function()
    it("should create string schema", function()
      local schema = Schema.String({minLength = 1, maxLength = 100})

      assert.is.equal("string", schema.type)
      assert.is.equal(1, schema.minLength)
      assert.is.equal(100, schema.maxLength)
    end)

    it("should create number schema", function()
      local schema = Schema.Number({minimum = 0, maximum = 100})

      assert.is.equal("number", schema.type)
      assert.is.equal(0, schema.minimum)
      assert.is.equal(100, schema.maximum)
    end)

    it("should create integer schema", function()
      local schema = Schema.Integer({minimum = 1})

      assert.is.equal("integer", schema.type)
      assert.is.equal(1, schema.minimum)
    end)

    it("should create boolean schema", function()
      local schema = Schema.Boolean()

      assert.is.equal("boolean", schema.type)
    end)

    it("should create null schema", function()
      local schema = Schema.Null()

      assert.is.equal("null", schema.type)
    end)
  end)

  describe("Enum builder", function()
    it("should create enum schema", function()
      local schema = Schema.Enum({"red", "green", "blue"})

      assert.is.same({"red", "green", "blue"}, schema.enum)
    end)
  end)

  describe("Const builder", function()
    it("should create const schema", function()
      local schema = Schema.Const("fixed-value")

      assert.is.equal("fixed-value", schema.const)
    end)
  end)

  describe("Composition builders", function()
    it("should create oneOf schema", function()
      local schema = Schema.OneOf({
        {type = "string"},
        {type = "number"}
      })

      assert.is_not_nil(schema.oneOf)
      assert.is.equal(2, #schema.oneOf)
    end)

    it("should create allOf schema", function()
      local schema = Schema.AllOf({
        {type = "string"},
        {minLength = 5}
      })

      assert.is_not_nil(schema.allOf)
      assert.is_equal(2, #schema.allOf)
    end)

    it("should create anyOf schema", function()
      local schema = Schema.AnyOf({
        {type = "string"},
        {type = "null"}
      })

      assert.is_not_nil(schema.anyOf)
      assert.is.equal(2, #schema.anyOf)
    end)
  end)

  describe("Schema validation", function()
    it("should validate a correct schema", function()
      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "number"}
      }, {required = {"name"}})

      local ok, err = Schema.Validate(schema)
      assert.is_true(ok)
      assert.is_nil(err)
    end)

    it("should reject schema with unknown keyword", function()
      local schema = {
        type = "object",
        unknown_keyword = true
      }

      local ok, err = Schema.Validate(schema)
      assert.is_false(ok)
      assert.is_not_nil(err)
      assert.is_not_nil(err:match("unknown_keyword"))
    end)

    it("should require type field", function()
      local schema = {properties = {}}

      local ok, err = Schema.Validate(schema)
      assert.is_false(ok)
      assert.is_not_nil(err:match("type"))
    end)
  end)

  describe("Normalization", function()
    it("should normalize Lua DSL to canonical form", function()
      local lua_schema = {
        type = "object",
        properties = {
          name = {type = "string"}
        },
        required = {"name"}
      }

      local normalized = Schema.Normalize(lua_schema)

      assert.is_not_nil(normalized)
      assert.is.equal("object", normalized.type)
    end)

    it("should load and normalize JSON schema file", function()
      -- This would test loading from external file
      -- For now, we'll test the normalization of a table that looks like JSON
      local json_like_schema = {
        type = "object",
        properties = {
          name = {type = "string"}
        }
      }

      local normalized = Schema.Normalize(json_like_schema)

      assert.is_not_nil(normalized)
      assert.is.equal("object", normalized.type)
    end)
  end)
end)
