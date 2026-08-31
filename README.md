<p align="center">
  <img src="https://santoku.dev/logo-santoku-socket.png" height="64" alt="santoku-socket">
</p>

# santoku-socket

An HTTP(S) client. Wraps luasec and ltn12 in a small request and response shape, with a
cancelable async handle and a millisecond `sleep`. A non-2xx status comes back as a
result, not an error.

## Install

```sh
luarocks install santoku-socket
```

## Example

```lua
local socket = require("santoku.socket")

local ok, resp = socket.fetch("https://example.com/")

if ok then
  print(resp.status, resp.body())
end
```

## Documentation

Runnable examples and the full API: [santoku.dev](https://santoku.dev/#santoku-socket).

For agents and LLM tooling: [llms.txt](https://santoku.dev/llms.txt) for the index,
[llms-full.txt](https://santoku.dev/llms-full.txt) for every documented example.

## Tests

The tests are the spec. For the exhaustive surface, read them:
[`test/spec/santoku/socket.lua`](test/spec/santoku/socket.lua).

## License

MIT, see [LICENSE](LICENSE).

## More examples

```lua
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
```

## Streams

`santoku.socket.stream` is a raw TLS stream driver (the contract consumed by
santoku-imap): `connect(opts, done)` with a push `data` callback, plus
`conn.step(ms)` for pumping on this blocking runtime. TLS verification is on
by default: the driver discovers a system CA bundle (Termux and common Linux
paths), verifies the chain, and matches the hostname against the
certificate's subjectAltName entries (with a commonName fallback), since
luasec alone verifies only the chain. No bundle found is a hard error;
`verify = false` is the explicit opt-out, and `conn.tls` reports the
verification state.
