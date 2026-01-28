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

    local response, status, response_headers = http.request({
        url = url,
        method = "POST",
        headers = headers,
        source = ltn12.source.string(request_body),
        sink = ltn12.sink.table(response_body),
    })

    if not response then
        error(string.format("HTTP request failed: %s", status))
    end

    if status >= 400 then
        error(string.format("HTTP Error %d: %s", status, table.concat(response_body)))
    end

    return dkjson.decode(table.concat(response_body))
end

function HttpClient:_parseURL(url)
    -- Simple URL parser - lua-http handles most of this
    return url
end

return HttpClient
