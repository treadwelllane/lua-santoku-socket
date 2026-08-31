local socket = require("socket")
local ssl = require("ssl")

local M = {}

M.ca_paths = {
  "/data/data/com.termux/files/usr/etc/tls/cert.pem",
  "/etc/ssl/certs/ca-certificates.crt",
  "/etc/ssl/cert.pem",
  "/etc/pki/tls/certs/ca-bundle.crt",
}

local function find_ca ()
  for i = 1, #M.ca_paths do
    local fh = io.open(M.ca_paths[i], "r")
    if fh then
      fh:close()
      return M.ca_paths[i]
    end
  end
end

local function cert_names (cert)
  local out = {}
  local ok, exts = pcall(cert.extensions, cert)
  if ok and type(exts) == "table" then
    for k, ext in pairs(exts) do
      if type(ext) == "table"
        and (k == "subjectAltName" or k == "2.5.29.17" or ext.dNSName) then
        local d = ext.dNSName or ext.DNS
        if type(d) == "table" then
          for i = 1, #d do
            if type(d[i]) == "string" then
              out[#out + 1] = string.lower(d[i])
            end
          end
        end
      end
    end
  end
  if #out == 0 then
    local oks, subj = pcall(cert.subject, cert)
    if oks and type(subj) == "table" then
      for i = 1, #subj do
        local e = subj[i]
        if type(e) == "table" and e.value
          and (e.name == "commonName" or e.oid == "2.5.4.3") then
          out[#out + 1] = string.lower(e.value)
        end
      end
    end
  end
  return out
end

local function match_host (host, names)
  host = string.lower(host)
  for i = 1, #names do
    local n = names[i]
    if n == host then
      return true
    end
    local suffix = string.match(n, "^%*%.(.+)$")
    if suffix and string.match(host, "^[^.]+%.(.+)$") == suffix then
      return true
    end
  end
  return false
end

M.cert_names = cert_names
M.match_host = match_host

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
  local tls = { verified = false }
  if opts.tls ~= false then
    local cafile = opts.cafile
    local capath = opts.capath
    if opts.verify ~= false and not cafile and not capath then
      cafile = find_ca()
      if not cafile then
        sock:close()
        return done(false,
          "no CA bundle found; pass cafile/capath or verify = false")
      end
    end
    local verifying = opts.verify ~= false
    local wrapped, werr = ssl.wrap(sock, {
      mode = "client",
      protocol = "any",
      options = { "all", "no_sslv2", "no_sslv3", "no_tlsv1", "no_tlsv1_1" },
      verify = verifying and "peer" or "none",
      cafile = cafile,
      capath = capath,
    })
    if not wrapped then
      sock:close()
      return done(false, werr)
    end
    if wrapped.sni then
      wrapped:sni(opts.sslname or opts.host)
    end
    wrapped:settimeout((opts.connect_timeout_ms or 30000) / 1000)
    local okh, herr = wrapped:dohandshake()
    if not okh then
      wrapped:close()
      return done(false, herr)
    end
    if verifying then
      local cert = wrapped.getpeercertificate
        and wrapped:getpeercertificate() or nil
      if not cert then
        wrapped:close()
        return done(false, "no peer certificate")
      end
      local names = cert_names(cert)
      local target = opts.sslname or opts.host
      if not match_host(target, names) then
        wrapped:close()
        return done(false, "hostname mismatch: certificate is for "
          .. (#names > 0 and table.concat(names, ", ") or "(no names found)")
          .. ", not " .. target)
      end
      tls.verified = true
      tls.cafile = cafile
      tls.capath = capath
      tls.names = names
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
    tls = tls,
    write = function (d)
      if closed then
        return false, "closed"
      end
      local i = 1
      while i <= #d do
        local n, werr2, np = sock:send(d, i)
        if n then
          i = n + 1
        elseif werr2 == "timeout" or werr2 == "wantwrite" then
          i = (np or (i - 1)) + 1
        else
          shut(werr2)
          return false, werr2
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
