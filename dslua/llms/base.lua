local BaseLLM = {}
BaseLLM.__index = BaseLLM

function BaseLLM.new(config)
    return setmetatable({
        _api_key = config.api_key,
        _base_url = config.base_url,
        _model = config.model,
        _timeout = config.timeout or 30000,
    }, BaseLLM)
end

function BaseLLM:APIKey()
    return self._api_key
end

function BaseLLM:Model()
    return self._model
end

function BaseLLM:BaseURL()
    return self._base_url
end

function BaseLLM:Complete(ctx, prompt, opts)
    error("Complete() must be implemented by subclass")
end

return BaseLLM
