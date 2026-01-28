local M = {}

function M.OpenAI(api_key, model, opts)
    return require("dslua.llms.providers.openai").new(api_key, model, opts)
end

return M
