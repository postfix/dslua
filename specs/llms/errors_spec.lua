describe("LLM Errors", function()
    local Errors = require("dslua.llms.errors")

    it("should create HTTPError", function()
        local err = Errors.HTTPError(404, "Not found")

        assert.is.equal("HTTPError", err.type)
        assert.is.equal(404, err.status)
        assert.is.equal("Not found", err.message)
    end)

    it("should create APIError", function()
        local err = Errors.APIError("invalid_request", "Missing required field")

        assert.is.equal("APIError", err.type)
        assert.is.equal("invalid_request", err.code)
        assert.is.equal("Missing required field", err.message)
    end)

    it("should create RateLimitError", function()
        local err = Errors.RateLimitError(60)

        assert.is.equal("RateLimitError", err.type)
        assert.is.equal(60, err.retry_after)
    end)

    it("should format error as string", function()
        local err = Errors.HTTPError(500, "Server error")
        local str = tostring(err)

        assert.is_not_nil(string.find(str, "HTTPError"))
        assert.is_not_nil(string.find(str, "500"))
    end)
end)
