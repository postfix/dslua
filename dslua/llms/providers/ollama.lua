local BaseLLM = require("dslua.llms.base")
local HttpClient = require("dslua.llms.http")
local Errors = require("dslua.llms.errors")

local Ollama = {}
Ollama.__index = Ollama
setmetatable(Ollama, {__index = BaseLLM})

function Ollama.new(model, opts)
    opts = opts or {}
    local config = {
        model = model,
        base_url = opts.base_url or "http://127.0.0.1:11434",
        timeout = opts.timeout or 60000,  -- Ollama can be slower
    }
    local self = BaseLLM.new(config)
    setmetatable(self, Ollama)
    self._http = HttpClient.new(config.timeout)
    return self
end

function Ollama:Complete(ctx, prompt, opts)
    opts = opts or {}
    local body = self:_buildRequestBody(prompt, opts)

    -- Ollama uses OpenAI-compatible API
    local response, err = self._http:Post(
        self._base_url .. "/v1/chat/completions",
        {
            ["Content-Type"] = "application/json",
        },
        body
    )

    if err then
        error(err)
    end

    return self:_parseResponse(response)
end

function Ollama:_buildRequestBody(prompt, opts)
    opts = opts or {}
    return {
        model = self._model,
        messages = {{role = "user", content = prompt}},
        stream = false,  -- Disable streaming for simplicity
    }
end

function Ollama:_parseResponse(response)
    if response.error then
        error(Errors.APIError(response.error.code, response.error.message))
    end

    return {
        content = response.choices[1].message.content,
        usage = response.usage,
        model = response.model,
    }
end

return Ollama
