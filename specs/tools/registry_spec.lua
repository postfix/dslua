describe("Tool Registry", function()
    local Registry
    local Tool

    setup(function()
        Registry = require("dslua.tools.registry")
        Tool = require("dslua.tools.base")
    end)

    it("should create new registry", function()
        local registry = Registry.new()
        assert.is.not_nil(registry)
    end)

    it("should register a tool", function()
        local registry = Registry.new()
        local tool = Tool.new("test_tool", {
            description = "Test tool",
            func = function(args) return {result = "ok"} end
        })

        registry:Register("test_tool", tool, {
            description = "Test tool",
            category = "test"
        })

        assert.is.truthy(registry:Has("test_tool"))
    end)

    it("should retrieve a registered tool", function()
        local registry = Registry.new()
        local tool = Tool.new("test_tool", {
            description = "Test tool",
            func = function(args) return {result = "ok"} end
        })

        registry:Register("test_tool", tool, {
            description = "Test tool",
            category = "test"
        })

        local retrieved = registry:Get("test_tool")
        assert.is.equal("test_tool", retrieved:Name())
    end)

    it("should throw error when registering duplicate tool", function()
        local registry = Registry.new()
        local tool1 = Tool.new("test_tool", {
            description = "Test tool 1",
            func = function(args) return {result = "ok"} end
        })
        local tool2 = Tool.new("test_tool", {
            description = "Test tool 2",
            func = function(args) return {result = "ok"} end
        })

        registry:Register("test_tool", tool1)

        assert.has_error(function()
            registry:Register("test_tool", tool2)
        end, "Tool 'test_tool' is already registered")
    end)

    it("should throw error when getting non-existent tool", function()
        local registry = Registry.new()

        assert.has_error(function()
            registry:Get("nonexistent")
        end, "Tool 'nonexistent' not found in registry")
    end)

    it("should list all tools", function()
        local registry = Registry.new()
        local tool1 = Tool.new("tool1", {
            description = "Tool 1",
            func = function(args) return {result = "ok"} end
        })
        local tool2 = Tool.new("tool2", {
            description = "Tool 2",
            func = function(args) return {result = "ok"} end
        })

        registry:Register("tool1", tool1, {category = "test"})
        registry:Register("tool2", tool2, {category = "test"})

        local all_tools = registry:List()
        assert.is.equal(2, #all_tools)
    end)

    it("should list tools by category", function()
        local registry = Registry.new()
        local tool1 = Tool.new("tool1", {
            description = "Tool 1",
            func = function(args) return {result = "ok"} end
        })
        local tool2 = Tool.new("tool2", {
            description = "Tool 2",
            func = function(args) return {result = "ok"} end
        })
        local tool3 = Tool.new("tool3", {
            description = "Tool 3",
            func = function(args) return {result = "ok"} end
        })

        registry:Register("tool1", tool1, {category = "test"})
        registry:Register("tool2", tool2, {category = "utility"})
        registry:Register("tool3", tool3, {category = "test"})

        local test_tools = registry:List("test")
        assert.is.equal(2, #test_tools)

        local utility_tools = registry:List("utility")
        assert.is.equal(1, #utility_tools)
    end)

    it("should return empty list when no tools in category", function()
        local registry = Registry.new()
        local tools = registry:List("nonexistent")
        assert.is.equal(0, #tools)
    end)

    it("should get tool metadata", function()
        local registry = Registry.new()
        local tool = Tool.new("test_tool", {
            description = "Test tool",
            func = function(args) return {result = "ok"} end
        })

        local metadata = {
            description = "Test tool",
            category = "test",
            parameters = {"param1", "param2"},
            examples = {"Example usage"}
        }

        registry:Register("test_tool", tool, metadata)

        local retrieved = registry:GetMetadata("test_tool")
        assert.is.equal("test", retrieved.category)
        assert.is.equal(2, #retrieved.parameters)
    end)

    it("should return empty metadata if not provided", function()
        local registry = Registry.new()
        local tool = Tool.new("test_tool", {
            description = "Test tool",
            func = function(args) return {result = "ok"} end
        })

        registry:Register("test_tool", tool)

        local retrieved = registry:GetMetadata("test_tool")
        assert.is.not_nil(retrieved)
    end)
end)
