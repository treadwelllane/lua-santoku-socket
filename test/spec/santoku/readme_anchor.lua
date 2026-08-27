local test = require("santoku.test")

local err = require("santoku.error")
local assert = err.assert

local validate = require("santoku.validate")
local eq = validate.isequal

local served = {}

package.loaded["ssl.https"] = {
  request = function (req)
    served.calls = served.calls + 1
    if req.sink then
      req.sink(served.body)
      req.sink(nil)
    end
    return 1, served.status, served.headers, "HTTP/1.1 " .. tostring(served.status)
  end
}

package.loaded["santoku.socket"] = nil
local socket = require("santoku.socket")

local function serving (status, body, headers)
  served.calls, served.status = 0, status
  served.body, served.headers = body or "", headers or {}
end

test("fetch a url and read the response", function ()
  serving(200, "pong")
  local ok, resp = socket.fetch("http://example.com/ping")
  assert(eq(true, ok))
  assert(eq(200, resp.status))
  assert(eq("pong", resp.body()))
end)

test("a non-2xx status comes back as not ok, not as an error", function ()
  serving(404, "nope")
  local ok, resp = socket.fetch("http://example.com/missing")
  assert(eq(false, ok))
  assert(eq(404, resp.status))
end)

test("response header keys are lowercased", function ()
  serving(200, "", { ["Content-Type"] = "text/plain" })
  local _, resp = socket.fetch("http://example.com/")
  assert(eq("text/plain", resp.headers["content-type"]))
end)

test("a request can be canceled before it is issued", function ()
  serving(200, "")
  local req = socket.request("http://example.com/job")
  req.cancel()
  local ok, resp = req.await()
  assert(eq(false, ok))
  assert(eq(true, resp.canceled))
  assert(eq(0, served.calls))
end)
