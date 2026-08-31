local socket = require("socket")
local ssl = require("ssl")

local M = {}

M.connect = function (opts, done)
  local sock, serr = socket.tcp()
  if not sock then
    return done(false, serr)
  end
  sock:settimeout((opts.connect_timeout_ms or 30000) / 1000)
  local okc, cerr = sock:connect(opts.host, opts.port)
  if not okc then
    sock:close()
    return done(false, cerr)
  end
  if opts.tls ~= false then
    local wrapped, werr = ssl.wrap(sock, {
      mode = "client",
      protocol = "any",
      options = { "all", "no_sslv2", "no_sslv3", "no_tlsv1", "no_tlsv1_1" },
      verify = (opts.cafile or opts.capath) and "peer" or "none",
      cafile = opts.cafile,
      capath = opts.capath,
    })
    if not wrapped then
      sock:close()
      return done(false, werr)
    end
    if wrapped.sni then
      wrapped:sni(opts.host)
    end
    wrapped:settimeout((opts.connect_timeout_ms or 30000) / 1000)
    local okh, herr = wrapped:dohandshake()
    if not okh then
      wrapped:close()
      return done(false, herr)
    end
    sock = wrapped
  end
  local closed = false
  local function shut (e)
    if closed then return end
    closed = true
    sock:close()
    if opts.closed then opts.closed(e) end
  end
  local conn
  conn = {
    write = function (d)
      if closed then
        return false, "closed"
      end
      local i = 1
      while i <= #d do
        local n, werr, np = sock:send(d, i)
        if n then
          i = n + 1
        elseif werr == "timeout" or werr == "wantwrite" then
          i = (np or (i - 1)) + 1
        else
          shut(werr)
          return false, werr
        end
      end
      return true
    end,
    step = function (ms)
      if closed then
        return false, "closed"
      end
      sock:settimeout((ms or 1000) / 1000)
      local d, rerr, partial = sock:receive(8192)
      local chunk = d or partial
      if chunk and #chunk > 0 then
        opts.data(chunk)
        if not d and rerr ~= "timeout" and rerr ~= "wantread" then
          shut(rerr)
          return false, rerr
        end
        return true
      end
      if rerr == "timeout" or rerr == "wantread" then
        return true, "timeout"
      end
      shut(rerr)
      return false, rerr
    end,
    close = function ()
      shut()
    end,
  }
  done(true, conn)
  return conn
end

return M
