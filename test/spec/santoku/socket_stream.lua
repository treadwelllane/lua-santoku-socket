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

local function fake_cert (cfg)
  return {
    extensions = function ()
      return cfg.exts or {}
    end,
    subject = function ()
      return cfg.subject or {}
    end,
  }
end

local function tls_sock (cfg)
  local f = fake_sock(cfg)
  f.sni = function (_, n)
    f.sniname = n
  end
  f.dohandshake = function ()
    if cfg.hsfail then
      return nil, "certificate verify failed"
    end
    return 1
  end
  f.getpeercertificate = function ()
    return cfg.cert
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

local CA = os.tmpname()
local fh = io.open(CA, "w")
fh:write("fake bundle")
fh:close()
stream.ca_paths = { CA }

local GMAIL_CERT = fake_cert({
  exts = { subjectAltName = { dNSName = { "imap.gmail.com", "*.gmail.com" } } },
})

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
  assert(got.tls.verified == false)
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

test("tls verifies by default with a discovered bundle", function ()
  state.sock = fake_sock({})
  state.tls_sock = tls_sock({ cert = GMAIL_CERT })
  local got
  stream.connect({
    host = "imap.gmail.com", port = 993,
    data = function () end,
  }, function (ok, c)
    assert(ok, "tls connect failed")
    got = c
  end)
  assert(state.wrap_cfg.verify == "peer")
  assert(state.wrap_cfg.cafile == CA)
  assert(state.tls_sock.sniname == "imap.gmail.com")
  assert(got.tls.verified == true)
  assert(got.tls.cafile == CA)
end)

test("wildcard san matches", function ()
  state.sock = fake_sock({})
  state.tls_sock = tls_sock({ cert = GMAIL_CERT })
  stream.connect({
    host = "pop.gmail.com", port = 995,
    data = function () end,
  }, function (ok, c)
    assert(ok, "wildcard match failed")
    assert(c.tls.verified == true)
  end)
end)

test("hostname mismatch rejected", function ()
  state.sock = fake_sock({})
  state.tls_sock = tls_sock({ cert = GMAIL_CERT })
  local res
  stream.connect({
    host = "imap.gmail.com", port = 993, sslname = "evil.example.com",
    data = function () end,
  }, function (ok, e)
    res = { ok = ok, e = e }
  end)
  assert(res.ok == false)
  assert(string.find(res.e, "hostname mismatch", 1, true))
  assert(state.tls_sock.closed)
end)

test("oid keyed san extension", function ()
  state.sock = fake_sock({})
  state.tls_sock = tls_sock({ cert = fake_cert({
    exts = { ["2.5.29.17"] = { dNSName = { "imap.gmail.com" } } },
  }) })
  stream.connect({
    host = "imap.gmail.com", port = 993,
    data = function () end,
  }, function (ok)
    assert(ok, "oid keyed san failed")
  end)
end)

test("common name fallback", function ()
  state.sock = fake_sock({})
  state.tls_sock = tls_sock({ cert = fake_cert({
    subject = { { name = "commonName", value = "imap.gmail.com" } },
  }) })
  stream.connect({
    host = "imap.gmail.com", port = 993,
    data = function () end,
  }, function (ok)
    assert(ok, "cn fallback failed")
  end)
end)

test("missing certificate rejected", function ()
  state.sock = fake_sock({})
  state.tls_sock = tls_sock({})
  local res
  stream.connect({
    host = "imap.gmail.com", port = 993,
    data = function () end,
  }, function (ok, e)
    res = { ok = ok, e = e }
  end)
  assert(res.ok == false)
  assert(res.e == "no peer certificate")
end)

test("no ca bundle is an error, not silent insecurity", function ()
  local saved = stream.ca_paths
  stream.ca_paths = {}
  state.sock = fake_sock({})
  local res
  stream.connect({
    host = "imap.gmail.com", port = 993,
    data = function () end,
  }, function (ok, e)
    res = { ok = ok, e = e }
  end)
  stream.ca_paths = saved
  assert(res.ok == false)
  assert(string.find(res.e, "no CA bundle", 1, true))
end)

test("verify false opts out entirely", function ()
  state.sock = fake_sock({})
  state.tls_sock = tls_sock({})
  local got
  stream.connect({
    host = "imap.gmail.com", port = 993, verify = false,
    data = function () end,
  }, function (ok, c)
    assert(ok, "opt-out connect failed")
    got = c
  end)
  assert(state.wrap_cfg.verify == "none")
  assert(got.tls.verified == false)
end)

test("explicit cafile skips discovery", function ()
  state.sock = fake_sock({})
  state.tls_sock = tls_sock({ cert = GMAIL_CERT })
  stream.connect({
    host = "imap.gmail.com", port = 993, cafile = "/my/ca.pem",
    data = function () end,
  }, function (ok)
    assert(ok)
  end)
  assert(state.wrap_cfg.cafile == "/my/ca.pem")
  assert(state.wrap_cfg.verify == "peer")
end)

test("handshake failure", function ()
  state.sock = fake_sock({})
  state.tls_sock = tls_sock({ hsfail = true })
  local res
  stream.connect({ host = "imap.gmail.com", port = 993,
    data = function () end,
  }, function (ok, e)
    res = { ok = ok, e = e }
  end)
  assert(res.ok == false)
  assert(res.e == "certificate verify failed")
  assert(state.tls_sock.closed)
end)

test("match_host exact and wildcard", function ()
  assert(stream.match_host("imap.gmail.com", { "imap.gmail.com" }))
  assert(stream.match_host("IMAP.GMAIL.COM", { "imap.gmail.com" }))
  assert(stream.match_host("pop.gmail.com", { "*.gmail.com" }))
  assert(not stream.match_host("gmail.com", { "*.gmail.com" }))
  assert(not stream.match_host("a.b.gmail.com", { "*.gmail.com" }))
  assert(not stream.match_host("evil.com", { "imap.gmail.com" }))
end)

test("cert_names shapes", function ()
  local san = stream.cert_names(fake_cert({
    exts = { subjectAltName = { dNSName = { "A.example", "b.example" } } },
  }))
  assert(#san == 2 and san[1] == "a.example")
  local oid = stream.cert_names(fake_cert({
    exts = { ["2.5.29.17"] = { dNSName = { "c.example" } } },
  }))
  assert(#oid == 1 and oid[1] == "c.example")
  local cn = stream.cert_names(fake_cert({
    subject = { { oid = "2.5.4.3", value = "d.example" } },
  }))
  assert(#cn == 1 and cn[1] == "d.example")
end)

os.remove(CA)
