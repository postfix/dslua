-- specs/tools/mcp_spec.lua
-- Tests for MCP (Model Context Protocol) Integration

describe("MCP Integration", function()
  local MCP = require("dslua.tools.mcp")

  -- Helper to mock HTTP request
  local function mock_http_response(response_body)
    local original_request = require("socket.http").request
    require("socket.http").request = function(opts)
      if opts.sink then
        opts.sink(response_body or "")
      end
      return 200, {}, "OK"
    end
    return original_request
  end

  local function restore_http_request(original)
    require("socket.http").request = original
  end

  describe("MCPClient", function()
    it("should create MCP client", function()
      local client = MCP.MCPClient.new()

      assert.is.equal("http://localhost:3000", client.server_url)
      assert.is.equal(30, client.timeout)
      assert.is.falsy(client.connected)
    end)

    it("should accept custom options", function()
      local client = MCP.MCPClient.new({
        server_url = "http://localhost:9000",
        timeout = 60
      })

      assert.is.equal("http://localhost:9000", client.server_url)
      assert.is.equal(60, client.timeout)
    end)

    it("should set client capabilities", function()
      local capabilities = {
        resources = {subscribe = true},
        tools = {list = true},
        prompts = {list = true}
      }

      local client = MCP.MCPClient.new({
        capabilities = capabilities
      })

      assert.is.equal(true, client.capabilities.resources.subscribe)
      assert.is.equal(true, client.capabilities.tools.list)
    end)
  end)

  describe("connect", function()
    it("should connect to MCP server", function()
      local response = [[{
        "result": {
          "serverInfo": {
            "name": "test-server",
            "version": "1.0.0"
          }
        }
      }]]

      local client = MCP.MCPClient.new()
      local original = mock_http_response(response)

      local server_info, err = client:connect()

      restore_http_request(original)

      assert.is.truthy(server_info)
      assert.is.equal("test-server", server_info.name)
      assert.is.equal(true, client.connected)
    end)

    it("should handle connection errors", function()
      local client = MCP.MCPClient.new()

      local original = mock_http_response(nil)
      require("socket.http").request = function(opts)
        return 500, {}, "Internal Server Error"
      end

      local server_info, err = client:connect()

      restore_http_request(original)

      assert.is.falsy(server_info)
      assert.is.truthy(err)
    end)
  end)

  describe("list_resources", function()
    it("should list available resources", function()
      local response = [[{
        "result": {
          "resources": [
            {"uri": "file:///test.txt", "name": "test.txt"},
            {"uri": "file:///data.json", "name": "data.json"}
          ]
        }
      }]]

      local client = MCP.MCPClient.new()
      client.connected = true  -- Simulate connected state
      local original = mock_http_response(response)

      local resources = client:list_resources()

      restore_http_request(original)

      assert.is.truthy(resources)
      assert.is.equal(2, #resources)
      assert.is.equal("test.txt", resources[1].name)
    end)

    it("should return empty list when no resources", function()
      local response = [[{"result": {"resources": []}}]]

      local client = MCP.MCPClient.new()
      client.connected = true
      local original = mock_http_response(response)

      local resources = client:list_resources()

      restore_http_request(original)

      assert.is.equal(0, #resources)
    end)
  end)

  describe("read_resource", function()
    it("should read resource content", function()
      local response = [[{
        "result": {
          "contents": [
            {"type": "text", "text": "Hello, world!"}
          ]
        }
      }]]

      local client = MCP.MCPClient.new()
      client.connected = true
      local original = mock_http_response(response)

      local result = client:read_resource("file:///test.txt")

      restore_http_request(original)

      assert.is.truthy(result)
      assert.is.truthy(result.contents)
    end)
  end)

  describe("list_tools", function()
    it("should list available tools", function()
      local response = [[{
        "result": {
          "tools": [
            {
              "name": "calculator",
              "description": "Basic calculator",
              "inputSchema": {"type": "object"}
            },
            {
              "name": "search",
              "description": "Search engine",
              "inputSchema": {"type": "object"}
            }
          ]
        }
      }]]

      local client = MCP.MCPClient.new()
      client.connected = true
      local original = mock_http_response(response)

      local tools = client:list_tools()

      restore_http_request(original)

      assert.is.truthy(tools)
      assert.is.equal(2, #tools)
      assert.is.equal("calculator", tools[1].name)
    end)
  end)

  describe("call_tool", function()
    it("should call tool with arguments", function()
      local response = [[{
        "result": {
          "content": [
            {"type": "text", "text": "Result: 42"}
          ]
        }
      }]]

      local client = MCP.MCPClient.new()
      client.connected = true
      local original = mock_http_response(response)

      local result = client:call_tool("calculator", {a = 2, b = 3})

      restore_http_request(original)

      assert.is.truthy(result)
      assert.is.truthy(result.content)
    end)

    it("should handle tool errors", function()
      local response = [[{
        "error": {
          "code": -32601,
          "message": "Tool not found"
        }
      }]]

      local client = MCP.MCPClient.new()
      client.connected = true
      local original = mock_http_response(response)

      local result, err = client:call_tool("unknown", {})

      restore_http_request(original)

      assert.is.falsy(result)
      assert.is.truthy(err)
    end)
  end)

  describe("list_prompts", function()
    it("should list available prompts", function()
      local response = [[{
        "result": {
          "prompts": [
            {"name": "greeting", "description": "Say hello"},
            {"name": "farewell", "description": "Say goodbye"}
          ]
        }
      }]]

      local client = MCP.MCPClient.new()
      client.connected = true
      local original = mock_http_response(response)

      local prompts = client:list_prompts()

      restore_http_request(original)

      assert.is.truthy(prompts)
      assert.is.equal(2, #prompts)
    end)
  end)

  describe("get_prompt", function()
    it("should get prompt template", function()
      local response = [[{
        "result": {
          "messages": [
            {"role": "user", "content": {"type": "text", "text": "Hello!"}}
          ]
        }
      }]]

      local client = MCP.MCPClient.new()
      client.connected = true
      local original = mock_http_response(response)

      local result = client:get_prompt("greeting", {})

      restore_http_request(original)

      assert.is.truthy(result)
      assert.is.truthy(result.messages)
    end)
  end)

  describe("MCPTool", function()
    it("should create MCP tool wrapper", function()
      local client = MCP.MCPClient.new()
      local tool = MCP.MCPTool.new(client, "calculator")

      assert.is.equal(client, tool.mcp_client)
      assert.is.equal("calculator", tool.tool_name)
    end)

    it("should execute tool", function()
      local client = MCP.MCPClient.new()
      client.connected = true

      local response = [[{
        "result": {
          "content": [
            {"type": "text", "text": "5"}
          ]
        }
      }]]

      local original = mock_http_response(response)

      local tool = MCP.MCPTool.new(client, "calculator")
      local result = tool:execute({a = 2, b = 3})

      restore_http_request(original)

      assert.is.equal("5", result)
    end)

    it("should concatenate multiple content parts", function()
      local client = MCP.MCPClient.new()
      client.connected = true

      local response = [[{
        "result": {
          "content": [
            {"type": "text", "text": "Line 1"},
            {"type": "text", "text": "Line 2"},
            {"type": "text", "text": "Line 3"}
          ]
        }
      }]]

      local original = mock_http_response(response)

      local tool = MCP.MCPTool.new(client, "multi_output")
      local result = tool:execute({})

      restore_http_request(original)

      assert.is.equal("Line 1\nLine 2\nLine 3", result)
    end)

    it("should refresh tool schema", function()
      local client = MCP.MCPClient.new()
      client.connected = true

      local response = [[{
        "result": {
          "tools": [
            {"name": "calculator", "description": "Calc tool"}
          ]
        }
      }]]

      local original = mock_http_response(response)

      local tool = MCP.MCPTool.new(client, "calculator")
      local success = tool:refresh_schema()

      restore_http_request(original)

      assert.is.equal(true, success)
      assert.is.truthy(tool.schema)
    end)
  end)

  describe("Helper Functions", function()
    it("should create MCP client with helper", function()
      local client = MCP.mcp_client({server_url = "http://localhost:9000"})

      assert.is.equal("http://localhost:9000", client.server_url)
    end)

    it("should create MCP tool with helper", function()
      local client = MCP.MCPClient.new()
      local tool = MCP.mcp_tool(client, "test_tool")

      assert.is.equal("test_tool", tool.tool_name)
    end)
  end)

  describe("Integration Tests", function()
    it("should work with complete MCP workflow", function()
      local client = MCP.MCPClient.new()
      local original = mock_http_response(nil)

      local call_count = 0
      local responses = {
        -- Connect response (call 1: initialize)
        '{"result": {"serverInfo": {"name": "test-server"}}}',
        -- Notification response (call 2: no response needed)
        '{}',
        -- List tools response (call 3)
        '{"result": {"tools": [{"name": "tool1", "description": "Tool 1"}]}}',
        -- Call tool response (call 4)
        '{"result": {"content": [{"type": "text", "text": "Success"}]}}'
      }

      require("socket.http").request = function(opts)
        call_count = call_count + 1
        local response = responses[call_count] or '{}'
        if opts.sink then
          opts.sink(response)
        end
        return 200, {}, "OK"
      end

      -- Connect (makes 2 calls: initialize + notification)
      local server_info = client:connect()
      assert.is.truthy(server_info)
      assert.is.equal(2, call_count)

      -- List tools
      local tools = client:list_tools()
      assert.is.truthy(tools)
      assert.is.equal(3, call_count)

      -- Call tool
      local result = client:call_tool("tool1", {})
      assert.is.truthy(result)
      assert.is.equal(4, call_count)

      restore_http_request(original)
    end)

    it("should handle multiple tool calls", function()
      local client = MCP.MCPClient.new()
      client.connected = true

      local call_count = 0
      local original = mock_http_response(nil)

      require("socket.http").request = function(opts)
        call_count = call_count + 1
        local response = string.format(
          '{"result": {"content": [{"type": "text", "text": "Call %d"}]}}',
          call_count
        )
        if opts.sink then
          opts.sink(response)
        end
        return 200, {}, "OK"
      end

      local tool = MCP.MCPTool.new(client, "test_tool")
      local result1 = tool:execute({})
      local result2 = tool:execute({})

      restore_http_request(original)

      assert.is.equal("Call 1", result1)
      assert.is.equal("Call 2", result2)
    end)
  end)

  describe("_next_id", function()
    it("should increment request IDs", function()
      local client = MCP.MCPClient.new()

      local id1 = client:_next_id()
      local id2 = client:_next_id()
      local id3 = client:_next_id()

      assert.is.equal(1, id1)
      assert.is.equal(2, id2)
      assert.is.equal(3, id3)
    end)
  end)
end)
