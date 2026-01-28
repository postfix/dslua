local BaseLLM = require("dslua.llms.base")
local HttpClient = require("dslua.llms.http")
local Errors = require("dslua.llms.errors")

local OpenAI = {}
OpenAI.__index = OpenAI
setmetatable(OpenAI, {__index = BaseLLM})

function OpenAI.new(api_key, model, opts)
    opts = opts or {}
    local config = {
        api_key = api_key,
        model = model,
        base_url = opts.base_url or "https://api.openai.com/v1",
        timeout = opts.timeout or 30000,
    }
    local self = BaseLLM.new(config)
    setmetatable(self, OpenAI)
    self._http = HttpClient.new(config.timeout)
    return self
end

function OpenAI:Complete(ctx, prompt, opts)
    opts = opts or {}
    local body = self:_buildRequestBody(prompt, opts)
    local headers = {
        ["Authorization"] = "Bearer " .. self._api_key,
        ["Content-Type"] = "application/json",
    }

    local response, err = self._http:Post(
        self._base_url .. "/chat/completions",
        headers,
        body
    )

    if err then
        error(err)
    end

    return self:_parseResponse(response)
end

function OpenAI:_buildRequestBody(prompt, opts)
    opts = opts or {}
    return {
        model = self._model,
        messages = {{role = "user", content = prompt}},
        temperature = opts.temperature or 0.7,
        max_tokens = opts.max_tokens or 1024,
    }
end

function OpenAI:_parseResponse(response)
    if response.error then
        error(Errors.APIError(response.error.code, response.error.message))
    end

    return {
        content = response.choices[1].message.content,
        usage = response.usage,
        model = response.model,
        finish_reason = response.choices[1].finish_reason,
    }
end

return OpenAI
