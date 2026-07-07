local https = require("ssl.https")
local ltn12 = require("ltn12")
local sys = require("santoku.system")
local arr = require("santoku.array")
local str = require("santoku.string")

local function do_fetch (url, opts)
  opts = opts or {}
  local chunks = {}
  local hdrs = opts.headers or {}
  if opts.body then
    hdrs["content-length"] = hdrs["content-length"] or tostring(#opts.body)
  end
  local ok, one, code, rheaders = pcall(https.request, {
    url = url,
    method = opts.method or "GET",
    headers = hdrs,
    sink = ltn12.sink.table(chunks),
    source = opts.body and ltn12.source.string(opts.body) or nil
  })
  if not ok then
    return false, {
      status = 0,
      headers = {},
      ok = false,
      error = one,
      body = function () return nil end
    }
  end
  if one == nil then
    return false, {
      status = 0,
      headers = {},
      ok = false,
      error = code,
      body = function () return nil end
    }
  end
  local body = arr.concat(chunks)
  local headers = {}
  if rheaders then
    for k, v in pairs(rheaders) do headers[str.lower(k)] = v end
  end
  local is2xx = code >= 200 and code < 300
  return is2xx, {
    status = code,
    headers = headers,
    ok = is2xx,
    body = function () return body end
  }
end

return {
  request = function (url, opts)
    opts = opts or {}
    local canceled = false
    return {
      cancel = function ()
        canceled = true
      end,
      await = function ()
        if canceled then
          return false, { status = 0, headers = {}, ok = false, canceled = true }
        end
        local ok, resp = do_fetch(url, opts)
        if canceled then
          return false, { status = 0, headers = {}, ok = false, canceled = true }
        end
        return ok, resp
      end
    }
  end,
  fetch = do_fetch,
  sleep = function (ms)
    sys.sleep(ms / 1000)
  end
}
