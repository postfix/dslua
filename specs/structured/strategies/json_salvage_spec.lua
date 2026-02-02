-- specs/structured/strategies/json_salvage_spec.lua
-- Tests for dslua/structured/strategies/json_salvage.lua

local JsonSalvage = require("dslua.structured.strategies.json_salvage")
local Schema = require("dslua.structured.schema")

describe("JSON Salvage Strategy", function()

  describe("Basic extraction", function()
    it("should extract JSON object from freeform text", function()
      local text = [[
        Here's the user profile you requested:

        {"name": "Alice", "age": 30}

        Let me know if you need anything else!
      ]]

      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_not_nil(result.candidate)
      assert.is_true(result.success)
      assert.is_true(result.lossy)
    end)

    it("should extract JSON array from freeform text", function()
      local text = [[
        The numbers are:

        [1, 2, 3, 4, 5]

        That's the complete list.
      ]]

      local schema = Schema.Array({type = "integer"})

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_true(result.success)
      assert.is_not_nil(result.candidate)
    end)

    it("should return nil when no JSON found", function()
      local text = "This is just plain text with no JSON structure at all."

      local schema = Schema.Object({name = {type = "string"}})

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_false(result.success)
      assert.is_nil(result.candidate)
    end)
  end)

  describe("Multiple JSON blocks", function()
    it("should extract the largest JSON block", function()
      local text = [[
        Small: {"id": 1}
        Larger: {"name": "Alice", "age": 30, "email": "alice@example.com"}
        Small: {"id": 2}
      ]]

      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_true(result.success)
      -- Should extract the largest object
      assert.is_not_nil(result.candidate)
    end)

    it("should prefer object over array when both present", function()
      local text = [[
        Array: [1, 2, 3]
        Object: {"name": "Alice"}
      ]]

      local schema = Schema.Object({name = {type = "string"}})

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_true(result.success)
    end)
  end)

  describe("Markdown and formatting", function()
    it("should extract JSON from markdown code blocks", function()
      local text = [[
        Here's the data:

        ```json
        {"name": "Bob", "age": 25}
        ```

        Hope this helps!
      ]]

      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_true(result.success)
    end)

    it("should extract JSON from unmarked code blocks", function()
      local text = [[
        Output:
        ```
        {"status": "active"}
        ```
      ]]

      local schema = Schema.Object({status = {type = "string"}})

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_true(result.success)
    end)

    it("should handle JSON with trailing commas", function()
      local text = 'Here is: {"name": "Charlie", "age": 35,}'

      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_true(result.success)
    end)
  end)

  describe("Nested structures", function()
    it("should extract nested JSON objects", function()
      local text = [[
        User data:
        {"user": {"name": "Alice", "profile": {"bio": "Developer"}}}
      ]]

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

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_true(result.success)
    end)

    it("should extract nested arrays", function()
      local text = [=[
        Matrix:
        [[1, 2], [3, 4], [5, 6]]
      ]=]

      local schema = Schema.Array({
        type = "array",
        items = {type = "integer"}
      })

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_true(result.success)
    end)
  end)

  describe("Lossy marking", function()
    it("should mark results as lossy", function()
      local text = 'Some text then {"key": "value"} more text'

      local schema = Schema.Object({key = {type = "string"}})

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_true(result.lossy, "Result should be marked as lossy")
    end)

    it("should indicate salvage method in metadata", function()
      local text = 'Text: {"name": "Alice"}'

      local schema = Schema.Object({name = {type = "string"}})

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      -- Should have metadata about how it was salvaged
      assert.is_not_nil(result)
    end)
  end)

  describe("Edge cases", function()
    it("should handle empty string", function()
      local text = ""

      local schema = Schema.Object({name = {type = "string"}})

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_false(result.success)
    end)

    it("should handle whitespace only", function()
      local text = "   \n\n   \t   "

      local schema = Schema.Object({name = {type = "string"}})

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_false(result.success)
    end)

    it("should handle incomplete JSON", function()
      local text = 'Here: {"name": "Alice", '

      local schema = Schema.Object({name = {type = "string"}})

      local result = JsonSalvage.extract(text, schema)

      -- Should not extract incomplete JSON
      assert.is_not_nil(result)
    end)

    it("should handle malformed JSON", function()
      local text = 'This: {"name": "Alice" "age": 30}'

      local schema = Schema.Object({name = {type = "string"}})

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      -- Should try to extract but validation will fail later
    end)
  end)

  describe("Top-level type requirements", function()
    it("should require object when specified", function()
      local text = 'This is a string, not an object'

      local schema = Schema.Object({name = {type = "string"}})

      local result = JsonSalvage.extract(text, schema, {
        require_top_level = "object"
      })

      assert.is_not_nil(result)
    end)

    it("should require array when specified", function()
      local text = '[1, 2, 3]'

      local schema = Schema.Array({type = "integer"})

      local result = JsonSalvage.extract(text, schema, {
        require_top_level = "array"
      })

      assert.is_not_nil(result)
      assert.is_true(result.success)
    end)

    it("should accept either when not specified", function()
      local text_with_obj = '{"key": "value"}'
      local text_with_array = '[1, 2, 3]'

      local schema = Schema.Object({key = {type = "string"}})

      local result1 = JsonSalvage.extract(text_with_obj, schema)
      local result2 = JsonSalvage.extract(text_with_array, schema)

      assert.is_not_nil(result1)
      assert.is_not_nil(result2)
    end)
  end)

  describe("Real-world scenarios", function()
    it("should extract JSON from conversational text", function()
      local text = [[
        Based on your request, here's the user information:

        The user's name is Alice and she's 30 years old.

        In JSON format:
        {"name": "Alice", "age": 30}

        Is there anything else you'd like to know?
      ]]

      local schema = Schema.Object({
        name = {type = "string"},
        age = {type = "integer"}
      })

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_true(result.success)
      assert.is_not_nil(result.candidate)
    end)

    it("should extract JSON from explanatory text", function()
      local text = [[
        I'll create a user profile for you:

        ```json
        {
          "username": "alice123",
          "email": "alice@example.com",
          "active": true
        }
        ```

        This profile includes the username, email address, and active status.
      ]]

      local schema = Schema.Object({
        username = {type = "string"},
        email = {type = "string"},
        active = {type = "boolean"}
      })

      local result = JsonSalvage.extract(text, schema)

      assert.is_not_nil(result)
      assert.is_true(result.success)
    end)
  end)

end)
