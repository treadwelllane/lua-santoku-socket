local http = require("socket.http")
local ltn12 = require("ltn12")
local sys = require("santoku.system")
local arr = require("santoku.array")
local str = require("santoku.string")

return {
  fetch = function (url, opts, done)
    opts = opts or {}
    local chunks = {}
    local ok, status, headers = pcall(http.request, {
      url = url,
      method = opts.method or "GET",
      headers = opts.headers,
      sink = ltn12.sink.table(chunks),
      source = opts.body and ltn12.source.string(opts.body) or nil
    })
    if not ok then
      return done(false, { status = 0, headers = {}, body = status })
    end
    local body = arr.concat(chunks)
    if headers then
      local h = {}
      for k, v in pairs(headers) do h[str.lower(k)] = v end
      headers = h
    end
    return done(status >= 200 and status < 300, {
      status = status,
      headers = headers or {},
      body = body,
      ok = status >= 200 and status < 300
    })
  end,
  sleep = function (ms, fn)
    sys.sleep(ms / 1000)
    return fn()
  end
}
