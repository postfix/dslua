local BaseLLM = require("dslua.llms.base")
local OpenAI = {}
OpenAI.__index = OpenAI
setmetatable(OpenAI, {__index = BaseLLM})

function OpenAI.new(api_key, model, opts)
    opts = opts or {}
    local config = {
        api_key = api_key,
        model = model,
        base_url = opts.base_url or "https://api.openai.com/v1",
        timeout = opts.timeout,
    }
    local self = BaseLLM.new(config)
    setmetatable(self, OpenAI)
    return self
end

function OpenAI:Complete(ctx, prompt, opts)
    -- HTTP client integration will be added in later tasks
    error("HTTP integration not yet implemented")
end

function OpenAI:_buildRequestBody(prompt, opts)
    opts = opts or {}
    return {
        model = self._model,
        messages = {{role = "user", content = prompt}},
        temperature = opts.temperature or 0.7,
    }
end

return OpenAI
