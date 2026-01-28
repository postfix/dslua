local M = {}

function M.OpenAI(api_key, model, opts)
    return require("dslua.llms.providers.openai").new(api_key, model, opts)
end

function M.Anthropic(api_key, model, opts)
    return require("dslua.llms.providers.anthropic").new(api_key, model, opts)
end

function M.Gemini(api_key, model, opts)
    return require("dslua.llms.providers.gemini").new(api_key, model, opts)
end

function M.Ollama(model, opts)
    return require("dslua.llms.providers.ollama").new(model, opts)
end

return M

