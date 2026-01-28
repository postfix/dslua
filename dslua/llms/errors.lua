local Errors = {}

function Errors.HTTPError(status, message)
    local err = {
        type = "HTTPError",
        status = status,
        message = message,
    }
    setmetatable(err, {
        __tostring = function(self)
            return string.format("[%s] %d: %s", self.type, self.status, self.message)
        end
    })
    return err
end

function Errors.APIError(code, message)
    local err = {
        type = "APIError",
        code = code,
        message = message,
    }
    setmetatable(err, {
        __tostring = function(self)
            return string.format("[%s] %s: %s", self.type, self.code, self.message)
        end
    })
    return err
end

function Errors.RateLimitError(retry_after)
    local err = {
        type = "RateLimitError",
        retry_after = retry_after,
    }
    setmetatable(err, {
        __tostring = function(self)
            return string.format("[%s] Retry after %d seconds", self.type, self.retry_after)
        end
    })
    return err
end

return Errors
