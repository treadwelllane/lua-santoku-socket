local test = require("santoku.test")
local err = require("santoku.error")
local assert = err.assert

local function fake_sock (cfg)
  local f = { sent = {}, recvi = 0, sends = 0 }
  f.connect = function (_, h, p)
    f.host, f.port = h, p
    if cfg.refuse then
      return nil, "connection refused"
    end
    return 1
  end
  f.settimeout = function (_, t)
    f.timeout = t
  end
  f.send = function (_, d, i)
    f.sends = f.sends + 1
    local s = cfg.sendscript and table.remove(cfg.sendscript, 1)
    if s then
      return nil, s.e, s.np
    end
    f.sent[#f.sent + 1] = string.sub(d, i or 1)
    return #d
  end
  f.receive = function ()
    f.recvi = f.recvi + 1
    local r = cfg.recvs and cfg.recvs[f.recvi]
    if not r then
      return nil, "timeout", ""
    end
    return r.d, r.e, r.p
  end
  f.close = function ()
    f.closed = true
  end
  return f
end

local state = {}

package.loaded["socket"] = {
  tcp = function ()
    return state.sock
  end,
}

package.loaded["ssl"] = {
  wrap = function (_, cfg)
    state.wrap_cfg = cfg
    if state.wrap_fail then
      return nil, "wrap failed"
    end
    return state.tls_sock
  end,
}

package.loaded["santoku.socket.stream"] = nil
local stream = require("santoku.socket.stream")

test("plain tcp roundtrip", function ()
  local chunks, closes = {}, {}
  state.sock = fake_sock({ recvs = {
    { d = "hel" },
    { e = "timeout", p = "lo" },
    { e = "timeout", p = "" },
    { e = "closed", p = "" },
  } })
  local got
  stream.connect({
    host = "h", port = 1, tls = false,
    data = function (c) chunks[#chunks + 1] = c end,
    closed = function (e) closes[#closes + 1] = e or "eof" end,
  }, function (ok, c)
    assert(ok, "connect failed")
    got = c
  end)
  assert(state.sock.host == "h" and state.sock.port == 1)
  assert(got.write("abc"))
  assert(state.sock.sent[1] == "abc")
  assert(got.step(10))
  assert(chunks[1] == "hel")
  assert(got.step(10))
  assert(chunks[2] == "lo")
  local ok2, e2 = got.step(10)
  assert(ok2 and e2 == "timeout")
  local ok3, e3 = got.step(10)
  assert(ok3 == false and e3 == "closed")
  assert(#closes == 1 and closes[1] == "closed")
  assert(state.sock.closed)
  local ok4 = got.step(10)
  assert(ok4 == false)
  assert(#closes == 1)
end)

test("write resumes after timeout", function ()
  state.sock = fake_sock({ sendscript = { { e = "timeout", np = 2 } } })
  local got
  stream.connect({
    host = "h", port = 1, tls = false,
    data = function () end,
  }, function (ok, c)
    assert(ok)
    got = c
  end)
  assert(got.write("abcde"))
  assert(state.sock.sends == 2)
  assert(state.sock.sent[1] == "cde")
end)

test("write failure closes once", function ()
  local closes = 0
  state.sock = fake_sock({ sendscript = { { e = "broken pipe" } } })
  local got
  stream.connect({
    host = "h", port = 1, tls = false,
    data = function () end,
    closed = function () closes = closes + 1 end,
  }, function (ok, c)
    assert(ok)
    got = c
  end)
  local ok2, e2 = got.write("x")
  assert(ok2 == false and e2 == "broken pipe")
  assert(closes == 1)
  got.close()
  assert(closes == 1)
end)

test("connect refused", function ()
  state.sock = fake_sock({ refuse = true })
  local res
  stream.connect({ host = "h", port = 1, tls = false,
    data = function () end,
  }, function (ok, e)
    res = { ok = ok, e = e }
  end)
  assert(res.ok == false)
  assert(res.e == "connection refused")
end)

test("tls wraps and handshakes", function ()
  state.sock = fake_sock({})
  state.tls_sock = fake_sock({ recvs = { { d = "secure" } } })
  state.tls_sock.sni = function (_, n)
    state.sni = n
  end
  state.tls_sock.dohandshake = function ()
    return 1
  end
  local got
  stream.connect({
    host = "imap.x.y", port = 993,
    data = function () end,
  }, function (ok, c)
    assert(ok, "tls connect failed")
    got = c
  end)
  assert(state.wrap_cfg.mode == "client")
  assert(state.wrap_cfg.verify == "none")
  assert(state.sni == "imap.x.y")
  assert(got.write("z"))
  assert(state.tls_sock.sent[1] == "z")
end)

test("tls verify peer with cafile", function ()
  state.sock = fake_sock({})
  state.tls_sock = fake_sock({})
  state.tls_sock.dohandshake = function ()
    return 1
  end
  stream.connect({
    host = "h", port = 993, cafile = "/ca.pem",
    data = function () end,
  }, function (ok)
    assert(ok)
  end)
  assert(state.wrap_cfg.verify == "peer")
  assert(state.wrap_cfg.cafile == "/ca.pem")
end)

test("handshake failure", function ()
  state.sock = fake_sock({})
  state.tls_sock = fake_sock({})
  state.tls_sock.dohandshake = function ()
    return nil, "certificate verify failed"
  end
  local res
  stream.connect({ host = "h", port = 993,
    data = function () end,
  }, function (ok, e)
    res = { ok = ok, e = e }
  end)
  assert(res.ok == false)
  assert(res.e == "certificate verify failed")
  assert(state.tls_sock.closed)
end)

test("step delivers to data callback in order", function ()
  local seen = ""
  state.sock = fake_sock({ recvs = {
    { e = "timeout", p = "" },
    { d = "aa" },
    { d = "bb" },
  } })
  local got
  stream.connect({
    host = "h", port = 1, tls = false,
    data = function (c) seen = seen .. c end,
  }, function (ok, c)
    assert(ok)
    got = c
  end)
  local ok1, e1 = got.step(10)
  assert(ok1 and e1 == "timeout")
  assert(got.step(10))
  assert(got.step(10))
  assert(seen == "aabb")
end)
