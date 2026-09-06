<p align="center">
  <img src="https://santoku.dev/logo-santoku-socket.png" height="64" alt="santoku-socket">
</p>

# santoku-socket

An HTTP(S) client. Wraps luasec and ltn12 in a small request and response shape, with a
cancelable async handle and a millisecond `sleep`. A non-2xx status comes back as a
result, not an error.

## Documentation

Runnable examples and the full API: [santoku.dev](https://santoku.dev/#santoku-socket).

For agents and LLM tooling: [llms.txt](https://santoku.dev/llms.txt) for the index,
[llms-full.txt](https://santoku.dev/llms-full.txt) for every documented example.

## License

MIT, see [LICENSE](LICENSE).

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
