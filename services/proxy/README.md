# FiremigProxy

FiremigProxy is a standalone OTP release that keeps public TCP sessions open while their
internal sandbox endpoint changes. The admin API binds to loopback by default; dynamic public
listeners bind to all IPv4 interfaces.

## Admin API

- `POST /internal/routes`
- `POST /internal/routes/:sandbox_id/begin-cutover`
- `PUT /internal/routes/:sandbox_id/endpoint`
- `GET /internal/routes/:sandbox_id/status`
- `GET /internal/routes/:sandbox_id` (status alias)
- `DELETE /internal/routes/:sandbox_id`

Create and endpoint-update bodies use this shape:

```json
{
  "sandboxId": "sandbox-123",
  "guestPort": 8080,
  "preferredProxyPort": 32000,
  "endpoint": {"host": "10.0.0.42", "port": 8080},
  "epoch": 1
}
```

`preferredProxyPort` is optional. Omitting it asks the OS for an available public port.

## Configuration

Production runtime variables include `ADMIN_PORT`, `PROXY_TOKEN`, `PROXY_BUFFER_BYTES`,
`PROXY_CONNECT_TIMEOUT_MS`, `PROXY_SEND_TIMEOUT_MS`, `PROXY_RETRY_BASE_MS`, and
`PROXY_RETRY_MAX_MS`.

When `PROXY_TOKEN` is non-empty, every `/internal` request requires an exact
`Authorization: Bearer <token>` header. `GET /health` remains unauthenticated.

Build and run a release with `MIX_ENV=prod mix release` and
`_build/prod/rel/firemig_proxy/bin/firemig_proxy start`.
