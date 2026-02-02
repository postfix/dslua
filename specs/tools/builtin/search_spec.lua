-- specs/tools/builtin/search_spec.lua
-- Tests for dslua/tools/builtin/search.lua

describe("SearchTool", function()
  local SearchTool = require("dslua.tools.builtin.search")

  describe("new", function()
    it("should create SearchTool instance", function()
      local tool = SearchTool.new()

      assert.is_truthy(tool)
      assert.is.equal("search", tool:Name())
    end)
  end)

  describe("Execute", function()
    it("should search with query parameter", function()
      local tool = SearchTool.new()
      local result = tool:Execute({query = "test query"})

      assert.is_truthy(result)
      assert.is_truthy(result:find("test query"))
    end)

    it("should return multiple results", function()
      local tool = SearchTool.new()
      local result = tool:Execute({query = "lua"})

      assert.is_truthy(result:find("Result 1"))
      assert.is_truthy(result:find("Result 2"))
      assert.is_truthy(result:find("Result 3"))
    end)

    it("should require query parameter", function()
      local tool = SearchTool.new()

      assert.has_error(function()
        tool:Execute({})
      end)
    end)

    it("should handle empty query", function()
      local tool = SearchTool.new()
      local result = tool:Execute({query = ""})

      assert.is_truthy(result)
    end)

    it("should handle special characters in query", function()
      local tool = SearchTool.new()
      local result = tool:Execute({query = "test & search"})

      assert.is_truthy(result)
    end)
  end)

  describe("Name", function()
    it("should return tool name", function()
      local tool = SearchTool.new()

      assert.is.equal("search", tool:Name())
    end)
  end)

  describe("Description", function()
    it("should return tool description", function()
      local tool = SearchTool.new()

      local desc = tool:Description()
      assert.is_truthy(desc)
      assert.is.truthy(type(desc) == "string")
    end)
  end)
end)
