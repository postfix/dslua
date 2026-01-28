local http = require("socket.http")
local ltn12 = require("ltn12")
local dkjson = require("dkjson")

local HttpClient = {}
HttpClient.__index = HttpClient

function HttpClient.new(timeout)
    return setmetatable({
        _timeout = timeout or 30000,
    }, HttpClient)
end

function HttpClient:Timeout()
    return self._timeout
end

function HttpClient:Post(url, headers, body)
    local request_body = dkjson.encode(body)
    local response_body = {}

    -- Parse URL to get host and path
    local parsed_url = self:_parseURL(url)

    -- Add Content-Length header
    headers["Content-Length"] = tostring(#request_body)

    local ok, response, status, response_headers = pcall(function()
        return http.request({
            url = url,
            method = "POST",
            headers = headers,
            source = ltn12.source.string(request_body),
            sink = ltn12.sink.table(response_body),
        })
    end)

    if not ok then
        error(string.format("HTTP request error: %s (url: %s)", tostring(response), url))
    end

    if not response then
        error(string.format("HTTP request failed: %s (url: %s)", tostring(status), url))
    end

    if type(status) == "number" and status >= 400 then
        error(string.format("HTTP Error %d: %s", status, table.concat(response_body)))
    end

    local body_text = table.concat(response_body)
    local decoded, decode_err = dkjson.decode(body_text)
    if not decoded then
        error(string.format("JSON decode error: %s", tostring(decode_err)))
    end

    return decoded
end

function HttpClient:_parseURL(url)
    -- Simple URL parser - lua-http handles most of this
    return url
end

return HttpClient
