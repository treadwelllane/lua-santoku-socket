# santoku-socket

An HTTP(S) client for the santoku ecosystem. It wraps luasec (`ssl.https`)
and ltn12 with a small request/response shape, an optional cancelable async
handle, and a millisecond `sleep`. Built on base [`santoku`](../lua-santoku/README.md)
and [`santoku-system`](../lua-santoku-system/README.md).

This README is a usage guide, not an API reference. The tests are the spec:
`test/spec/santoku/socket.lua` exercises the full surface.

For the underlying request semantics (TLS, redirects, the request table,
ltn12 sources/sinks), see the luasec and luasocket documentation.

## Entry points

- `fetch(url, opts)` performs a blocking request and returns `ok, resp`. `ok`
  is true for a 2xx status. `opts` carries `method` (default `GET`),
  `headers`, and `body`; a `content-length` header is derived from the body
  when not set. `resp` has `status`, `ok`, `headers` (keys lowercased), and
  `body`, a function returning the response text. A transport failure returns
  `false` and a response with `status = 0` and an `error` field.
- `request(url, opts)` returns a handle with `await()` (runs the fetch and
  returns `ok, resp`) and `cancel()`. Canceling before `await` short-circuits
  to `false` and `{ status = 0, canceled = true }` without issuing a request.
- `sleep(ms)` sleeps for `ms` milliseconds via `santoku.system`.

## Snippet

```lua
local socket = require("santoku.socket")

local ok, resp = socket.fetch("https://example/ping")
if ok then
  print(resp.status, resp.body())          -- 200  "pong"
  print(resp.headers["content-type"])      -- header keys are lowercased
end

local ok2, resp2 = socket.fetch("https://example/echo", {
  method = "POST",
  body = "hello",                          -- content-length derived from body
})

local req = socket.request("https://example/job")
req.cancel()
local ok3, r = req.await()                  -- false, { status = 0, canceled = true }
```

covers: `test/spec/santoku/socket.lua` (fetch 2xx/non-2xx, request body and
content-length, request/await, cancel, transport failure).

## License

MIT License

Copyright 2025 Birch Point SWE

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
