local BaseLLM = require("dslua.llms.base")
local HttpClient = require("dslua.llms.http")
local Errors = require("dslua.llms.errors")

local Anthropic = {}
Anthropic.__index = Anthropic
setmetatable(Anthropic, {__index = BaseLLM})

function Anthropic.new(api_key, model, opts)
    opts = opts or {}
    local config = {
        api_key = api_key,
        model = model,
        base_url = opts.base_url or "https://api.anthropic.com/v1",
        timeout = opts.timeout or 60000,
    }
    local self = BaseLLM.new(config)
    setmetatable(self, Anthropic)
    self._http = HttpClient.new(config.timeout)
    return self
end

function Anthropic:Complete(ctx, prompt, opts)
    opts = opts or {}
    local body = self:_buildRequestBody(prompt, opts)
    local headers = {
        ["x-api-key"] = self._api_key,
        ["anthropic-version"] = "2023-06-01",
        ["Content-Type"] = "application/json",
    }

    local response = self._http:Post(
        self._base_url .. "/messages",
        headers,
        body
    )

    return self:_parseResponse(response)
end

function Anthropic:_buildRequestBody(prompt, opts)
    return {
        model = self._model,
        max_tokens = opts.max_tokens or 4096,
        messages = {{role = "user", content = prompt}},
    }
end

function Anthropic:_parseResponse(response)
    if response.error then
        error(Errors.APIError(response.error.type, response.error.message))
    end

    return {
        content = response.content[1].text,
        usage = response.usage,
        model = response.model,
        stop_reason = response.stop_reason,
    }
end

return Anthropic
