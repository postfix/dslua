local BaseAgent = {}
BaseAgent.__index = BaseAgent

function BaseAgent.new(signature, opts)
    opts = opts or {}
    local self = setmetatable({}, BaseAgent)

    self._signature = signature
    self._max_iterations = opts.max_iterations or 10
    self._output_mode = opts.output_mode or "simple"
    self._retry_config = opts.retry_config or {
        max_retries = 3,
        initial_delay = 100,
        backoff_multiplier = 2.0,
        retryable_errors = {"timeout", "connection refused"}
    }

    return self
end

function BaseAgent:Execute(ctx, input, opts)
    opts = opts or {}

    local state = self:_initialize(input, opts)
    local max_iter = opts.max_iterations or self._max_iterations

    for iteration = 1, max_iter do
        state.current_iteration = iteration

        local step_result = self:_executeStep(ctx, state)

        if step_result and step_result.stop then
            break
        end

        if self:_shouldStop(state) then
            break
        end
    end

    return self:_formatResult(state, self._output_mode)
end

function BaseAgent:_initialize(input, opts)
    error("_initialize must be implemented by subclass")
end

function BaseAgent:_shouldStop(state)
    error("_shouldStop must be implemented by subclass")
end

function BaseAgent:_executeStep(ctx, state)
    error("_executeStep must be implemented by subclass")
end

function BaseAgent:_updateSummary(state, step)
    error("_updateSummary must be implemented by subclass")
end

function BaseAgent:_formatResult(state, mode)
    if mode == "simple" then
        return self:_formatSimple(state)
    elseif mode == "structured" then
        return self:_formatStructured(state)
    else
        error("Unknown output mode: " .. tostring(mode))
    end
end

function BaseAgent:_formatSimple(state)
    error("_formatSimple must be implemented by subclass")
end

function BaseAgent:_formatStructured(state)
    error("_formatStructured must be implemented by subclass")
end

function BaseAgent:_executeWithRetry(ctx, func, config)
    config = config or self._retry_config

    local last_error
    for attempt = 1, config.max_retries + 1 do
        local success, result = pcall(func, ctx)

        if success then
            return true, result
        end

        last_error = result

        if attempt < config.max_retries + 1 and self:_isRetryableError(result, config.retryable_errors) then
            local delay = config.initial_delay * math.pow(config.backoff_multiplier, attempt - 1)
            -- Sleep for delay milliseconds
            -- Note: In Lua, we'd use a platform-specific sleep function
            -- For now, this is a placeholder
        else
            break
        end
    end

    return false, last_error
end

function BaseAgent:_isRetryableError(error, retryable_errors)
    local error_msg = tostring(error)
    for _, pattern in ipairs(retryable_errors) do
        if error_msg:lower():find(pattern:lower()) then
            return true
        end
    end
    return false
end

return BaseAgent
