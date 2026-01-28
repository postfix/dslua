describe("HttpClient", function()
    it("should create client with default timeout", function()
        local HttpClient = require("dslua.llms.http")
        local client = HttpClient.new()

        assert.is.equal(30000, client._timeout)
    end)

    it("should create client with custom timeout", function()
        local HttpClient = require("dslua.llms.http")
        local client = HttpClient.new(60000)

        assert.is.equal(60000, client._timeout)
    end)

    it("should encode JSON body", function()
        local HttpClient = require("dslua.llms.http")
        local dkjson = require("dkjson")

        -- Test JSON encoding separately
        local body = {test = "value", number = 42}
        local json = dkjson.encode(body)

        assert.is_not_nil(string.find(json, '"test"'))
        assert.is_not_nil(string.find(json, '"value"'))
    end)

    it("should decode JSON response", function()
        local HttpClient = require("dslua.llms.http")
        local dkjson = require("dkjson")

        local json = '{"result": "success", "count": 5}'
        local decoded = dkjson.decode(json)

        assert.is.equal("success", decoded.result)
        assert.is.equal(5, decoded.count)
    end)
end)
