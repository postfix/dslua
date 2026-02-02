-- dslua/tools/mcp.lua
-- Model Context Protocol (MCP) Integration

local M = {}

-- =============================================================================
-- MCP Client
-- =============================================================================

M.MCPClient = {}
M.MCPClient.__index = M.MCPClient

function M.MCPClient.new(opts)
  opts = opts or {}

  local self = {
    -- Server configuration
    server_url = opts.server_url or "http://localhost:3000",
    timeout = opts.timeout or 30,

    -- Client info
    client_name = opts.client_name or "dslua-mcp-client",
    client_version = opts.client_version or "1.0.0",

    -- Capabilities
    capabilities = opts.capabilities or {
      resources = {},
      tools = {},
      prompts = {}
    },

    -- Connection state
    connected = false,
    server_info = nil,

    -- Request ID counter
    request_id = 0
  }

  setmetatable(self, M.MCPClient)
  return self
end

-- Connect to MCP server
function M.MCPClient:connect()
  local request = {
    jsonrpc = "2.0",
    id = self:_next_id(),
    method = "initialize",
    params = {
      protocolVersion = "2024-11-05",
      capabilities = self.capabilities,
      clientInfo = {
        name = self.client_name,
        version = self.client_version
      }
    }
  }

  local response, err = self:_send_request(request)
  if err then
    return nil, err
  end

  if response.result then
    self.server_info = response.result.serverInfo
    self.connected = true

    -- Send initialized notification
    self:_send_notification({
      jsonrpc = "2.0",
      method = "notifications/initialized"
    })

    return self.server_info
  end

  return nil, response.error
end

-- List available resources
function M.MCPClient:list_resources(opts)
  opts = opts or {}

  local request = {
    jsonrpc = "2.0",
    id = self:_next_id(),
    method = "resources/list",
    params = {}
  }

  local response, err = self:_send_request(request)
  if err then
    return nil, err
  end

  return response.result and response.result.resources or {}
end

-- Read resource content
function M.MCPClient:read_resource(uri, opts)
  opts = opts or {}

  local request = {
    jsonrpc = "2.0",
    id = self:_next_id(),
    method = "resources/read",
    params = {
      uri = uri
    }
  }

  local response, err = self:_send_request(request)
  if err then
    return nil, err
  end

  return response.result
end

-- List available tools
function M.MCPClient:list_tools()
  local request = {
    jsonrpc = "2.0",
    id = self:_next_id(),
    method = "tools/list",
    params = {}
  }

  local response, err = self:_send_request(request)
  if err then
    return nil, err
  end

  return response.result and response.result.tools or {}
end

-- Call tool
function M.MCPClient:call_tool(name, arguments, opts)
  opts = opts or {}

  local request = {
    jsonrpc = "2.0",
    id = self:_next_id(),
    method = "tools/call",
    params = {
      name = name,
      arguments = arguments or {}
    }
  }

  local response, err = self:_send_request(request)
  if err then
    return nil, err
  end

  return response.result
end

-- List available prompts
function M.MCPClient:list_prompts()
  local request = {
    jsonrpc = "2.0",
    id = self:_next_id(),
    method = "prompts/list",
    params = {}
  }

  local response, err = self:_send_request(request)
  if err then
    return nil, err
  end

  return response.result and response.result.prompts or {}
end

-- Get prompt
function M.MCPClient:get_prompt(name, arguments, opts)
  opts = opts or {}

  local request = {
    jsonrpc = "2.0",
    id = self:_next_id(),
    method = "prompts/get",
    params = {
      name = name,
      arguments = arguments or {}
    }
  }

  local response, err = self:_send_request(request)
  if err then
    return nil, err
  end

  return response.result
end

-- Send request to server
function M.MCPClient:_send_request(request)
  local http = require("socket.http")
  local ltn12 = require("ltn12")
  local json = require("cjson")

  local request_body = json.encode(request)

  local response_body = {}
  local code, headers, status = http.request{
    url = self.server_url,
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["Content-Length"] = tostring(#request_body)
    },
    source = ltn12.source.string(request_body),
    sink = ltn12.sink.table(response_body),
    timeout = self.timeout
  }

  if code ~= 200 then
    return nil, string.format("HTTP %d: %s", code, status or "Unknown error")
  end

  local response_text = table.concat(response_body)
  local response = json.decode(response_text)

  if response.error then
    return nil, response.error.message or "Unknown error"
  end

  return response
end

-- Send notification (no response expected)
function M.MCPClient:_send_notification(request)
  local http = require("socket.http")
  local ltn12 = require("ltn12")
  local json = require("cjson")

  local request_body = json.encode(request)

  http.request{
    url = self.server_url,
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json",
      ["Content-Length"] = tostring(#request_body)
    },
    source = ltn12.source.string(request_body),
    timeout = self.timeout
  }
end

-- Get next request ID
function M.MCPClient:_next_id()
  self.request_id = self.request_id + 1
  return self.request_id
end

-- =============================================================================
-- MCP Tool Wrapper
-- =============================================================================

M.MCPTool = {}
M.MCPTool.__index = M.MCPTool

function M.MCPTool.new(mcp_client, tool_name)
  local self = {
    mcp_client = mcp_client,
    tool_name = tool_name,
    schema = nil
  }

  setmetatable(self, M.MCPTool)
  return self
end

-- Execute tool
function M.MCPTool:execute(input)
  local result, err = self.mcp_client:call_tool(self.tool_name, input)

  if err then
    return nil, err
  end

  -- Extract content from result
  if result.content and #result.content > 0 then
    local text_parts = {}
    for _, item in ipairs(result.content) do
      if item.type == "text" then
        table.insert(text_parts, item.text)
      end
    end
    return table.concat(text_parts, "\n")
  end

  return result
end

-- Refresh tool schema
function M.MCPTool:refresh_schema()
  local tools = self.mcp_client:list_tools()

  for _, tool in ipairs(tools) do
    if tool.name == self.tool_name then
      self.schema = tool
      return true
    end
  end

  return false
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

function M.mcp_client(opts)
  return M.MCPClient.new(opts)
end

function M.mcp_tool(client, tool_name)
  return M.MCPTool.new(client, tool_name)
end

return M
