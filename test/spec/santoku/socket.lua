local test = require("santoku.test")

local err = require("santoku.error")
local assert = err.assert

local validate = require("santoku.validate")
local eq = validate.isequal





local stub = {}

local function reset (cfg)
  cfg = cfg or {}
  stub.status = cfg.status or 200
  stub.body = cfg.body or ""
  stub.headers = cfg.headers or {}
  stub.fail = cfg.fail or false
  stub.nilreturn = cfg.nilreturn or false
  stub.calls = 0
  stub.last = nil
end

package.loaded["ssl.https"] = {
  request = function (req)
    stub.calls = stub.calls + 1
    stub.last = req
    if stub.fail then
      error("connection refused")
    end
    if stub.nilreturn then
      return nil, "request failed"
    end
    if req.sink then
      req.sink(stub.body)
      req.sink(nil)
    end
    return 1, stub.status, stub.headers, "HTTP/1.1 " .. tostring(stub.status)
  end
}
package.loaded["santoku.socket"] = nil
local socket = require("santoku.socket")

test("fetch returns ok for a 2xx status", function ()
  reset({ status = 200, body = "pong" })
  local ok, resp = socket.fetch("http://x/ping")
  assert(eq(true, ok))
  assert(eq(200, resp.status))
  assert(eq(true, resp.ok))
  assert(eq("pong", resp.body()))
  assert(eq(1, stub.calls))
end)

test("fetch returns not-ok for a non-2xx status", function ()
  reset({ status = 404, body = "nope" })
  local ok, resp = socket.fetch("http://x/missing")
  assert(eq(false, ok))
  assert(eq(404, resp.status))
  assert(eq(false, resp.ok))
  assert(eq("nope", resp.body()))
end)

test("fetch lowercases response header keys", function ()
  reset({ status = 200, headers = { ["Content-Type"] = "text/plain" } })
  local _, resp = socket.fetch("http://x/")
  assert(eq("text/plain", resp.headers["content-type"]))
end)

test("fetch derives content-length from the body", function ()
  reset({ status = 200 })
  socket.fetch("http://x/echo", { method = "POST", body = "hello" })
  assert(eq("POST", stub.last.method))
  assert(eq("5", stub.last.headers["content-length"]))
end)

test("request await runs the fetch", function ()
  reset({ status = 200, body = "x" })
  local req = socket.request("http://x/job")
  local ok, resp = req.await()
  assert(eq(true, ok))
  assert(eq("x", resp.body()))
end)

test("request cancel short-circuits without issuing a request", function ()
  reset({ status = 200 })
  local req = socket.request("http://x/job")
  req.cancel()
  local ok, resp = req.await()
  assert(eq(false, ok))
  assert(eq(0, resp.status))
  assert(eq(true, resp.canceled))
  assert(eq(0, stub.calls))
end)

test("fetch reports a raised transport failure", function ()
  reset({ fail = true })
  local ok, resp = socket.fetch("http://x/down")
  assert(eq(false, ok))
  assert(eq(0, resp.status))
  assert(resp.error ~= nil)
end)

test("fetch reports a request-level nil failure", function ()
  reset({ nilreturn = true })
  local ok, resp = socket.fetch("http://x/down")
  assert(eq(false, ok))
  assert(eq(0, resp.status))
  assert(eq("request failed", resp.error))
end)
