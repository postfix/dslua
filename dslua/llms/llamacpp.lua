-- dslua/llms/llamacpp.lua
-- LlamaCPP LLM Provider for local model inference

local M = {}
local http = require("socket.http")
local ltn12 = require("ltn12")
local json = require("cjson")

-- =============================================================================
-- LlamaCPP Provider
-- =============================================================================

M.LlamaCPP = {}
M.LlamaCPP.__index = M.LlamaCPP

function M.LlamaCPP.new(opts)
  opts = opts or {}

  local self = {
    -- Server configuration
    base_url = opts.base_url or "http://localhost:8080",
    timeout = opts.timeout or 120,

    -- Model parameters
    model = opts.model,
    temperature = opts.temperature or 0.7,
    max_tokens = opts.max_tokens or 4096,
    top_p = opts.top_p or 0.9,
    top_k = opts.top_k or 40,
    repeat_penalty = opts.repeat_penalty or 1.1,

    -- Generation settings
    num_predict = opts.num_predict or 256,
    stop = opts.stop or {},
    n_keep = opts.n_keep or 0,

    -- Streaming
    stream = opts.stream or false,

    -- Cache
    cache = opts.cache or {}
  }

  setmetatable(self, M.LlamaCPP)
  return self
end

-- Generate completion
function M.LlamaCPP:generate(prompt, opts)
  opts = opts or {}

  local request = {
    prompt = prompt,
    model = self.model,
    temperature = opts.temperature or self.temperature,
    max_tokens = opts.max_tokens or self.max_tokens,
    top_p = opts.top_p or self.top_p,
    top_k = opts.top_k or self.top_k,
    repeat_penalty = opts.repeat_penalty or self.repeat_penalty,
    num_predict = opts.num_predict or self.num_predict,
    stop = opts.stop or self.stop,
    n_keep = opts.n_keep or self.n_keep,
    stream = opts.stream or self.stream
  }

  -- Add cache if prompt was seen before
  local cache_key = self:_cache_key(prompt, opts)
  if self.cache[cache_key] and not opts.nocache then
    return self.cache[cache_key]
  end

  -- Make request
  local response, err = self:_request("/completion", request)

  if err then
    return nil, err
  end

  -- Cache result
  if not opts.nocache then
    self.cache[cache_key] = response
  end

  return response
end

-- Generate with chat format
function M.LlamaCPP:chat(messages, opts)
  opts = opts or {}

  -- Convert messages to prompt format
  local prompt = self:_format_chat(messages)

  return self:generate(prompt, opts)
end

-- Format messages as chat prompt
function M.LlamaCPP:_format_chat(messages)
  local prompt = ""

  for _, msg in ipairs(messages) do
    local role = msg.role or "user"
    local content = msg.content or ""

    if role == "system" then
      prompt = prompt .. "### System:\n" .. content .. "\n"
    elseif role == "user" then
      prompt = prompt .. "### User:\n" .. content .. "\n"
    elseif role == "assistant" then
      prompt = prompt .. "### Assistant:\n" .. content .. "\n"
    end
  end

  prompt = prompt .. "### Assistant:\n"

  return prompt
end

-- Make HTTP request to LlamaCPP server
function M.LlamaCPP:_request(endpoint, data)
  local url = self.base_url .. endpoint

  local request_body = json.encode(data)

  local response_body = {}
  local code, headers, status = http.request{
    url = url,
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

  -- Extract content from response
  if response.content then
    return {
      content = response.content,
      text = response.content,
      finish_reason = response.stop_reason or "length",
      usage = {
        prompt_tokens = response.tokens_evaluated or 0,
        completion_tokens = response.tokens_generated or 0,
        total_tokens = (response.tokens_evaluated or 0) + (response.tokens_generated or 0)
      },
      model = response.model or self.model
    }
  end

  return response
end

-- Generate cache key
function M.LlamaCPP:_cache_key(prompt, opts)
  local key = prompt .. "_"
  key = key .. (opts.temperature or self.temperature) .. "_"
  key = key .. (opts.max_tokens or self.max_tokens)
  return key
end

-- Clear cache
function M.LlamaCPP:clear_cache()
  self.cache = {}
end

-- Get model info
function M.LlamaCPP:model_info()
  local response_body = {}

  local code, headers, status = http.request{
    url = self.base_url .. "/props",
    method = "GET",
    sink = ltn12.sink.table(response_body),
    timeout = self.timeout
  }

  if code ~= 200 then
    return nil, "Failed to get model info"
  end

  local response_text = table.concat(response_body)
  return json.decode(response_text)
end

-- Check server health
function M.LlamaCPP:health()
  local response_body = {}

  local code = http.request{
    url = self.base_url .. "/health",
    method = "GET",
    sink = ltn12.sink.table(response_body),
    timeout = 5
  }

  return code == 200
end

-- Tokenize text
function M.LlamaCPP:tokenize(text)
  local response_body = {}

  local request_body = json.encode({content = text})

  local code, headers, status = http.request{
    url = self.base_url .. "/tokenize",
    method = "POST",
    headers = {
      ["Content-Type"] = "application/json"
    },
    source = ltn12.source.string(request_body),
    sink = ltn12.sink.table(response_body),
    timeout = self.timeout
  }

  if code ~= 200 then
    return nil, "Failed to tokenize"
  end

  local response_text = table.concat(response_body)
  local response = json.decode(response_text)

  return response.tokens
end

-- =============================================================================
-- Helper Functions
-- =============================================================================

function M.llamacpp(opts)
  return M.LlamaCPP.new(opts)
end

return M
