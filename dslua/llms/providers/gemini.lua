local BaseLLM = require("dslua.llms.base")
local HttpClient = require("dslua.llms.http")
local Errors = require("dslua.llms.errors")

local Gemini = {}
Gemini.__index = Gemini
setmetatable(Gemini, {__index = BaseLLM})

function Gemini.new(api_key, model, opts)
    opts = opts or {}
    local config = {
        api_key = api_key,
        model = model,
        base_url = opts.base_url or "https://generativelanguage.googleapis.com/v1beta",
        timeout = opts.timeout or 30000,
    }
    local self = BaseLLM.new(config)
    setmetatable(self, Gemini)
    self._http = HttpClient.new(config.timeout)
    return self
end

function Gemini:Complete(ctx, prompt, opts)
    opts = opts or {}
    local body = self:_buildRequestBody(prompt, opts)

    -- API key in URL query parameter
    local url = string.format("%s/models/%s:generateContent?key=%s",
        self._base_url,
        self._model,
        self._api_key
    )

    local headers = {
        ["Content-Type"] = "application/json",
    }

    local response = self._http:Post(url, headers, body)

    return self:_parseResponse(response)
end

function Gemini:_buildRequestBody(prompt, opts)
    return {
        contents = {{
            parts = {{text = prompt}}
        }},
        generationConfig = {
            temperature = opts.temperature or 0.7,
            maxOutputTokens = opts.max_tokens or 1024,
        }
    }
end

function Gemini:_parseResponse(response)
    if response.error then
        error(Errors.APIError(response.error.code, response.error.message))
    end

    return {
        content = response.candidates[1].content.parts[1].text,
        usage = response.usageMetadata,
        model = self._model,
        finishReason = response.candidates[1].finishReason,
    }
end

return Gemini
