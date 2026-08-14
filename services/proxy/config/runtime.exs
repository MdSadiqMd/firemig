import Config

if config_env() == :prod do
  parse_integer = fn name, default ->
    name
    |> System.get_env(Integer.to_string(default))
    |> String.to_integer()
  end

  config :firemig_proxy,
    admin_port: parse_integer.("ADMIN_PORT", 4001),
    buffer_bytes: parse_integer.("PROXY_BUFFER_BYTES", 262_144),
    connect_timeout_ms: parse_integer.("PROXY_CONNECT_TIMEOUT_MS", 1_000),
    internal_send_timeout_ms: parse_integer.("PROXY_SEND_TIMEOUT_MS", 5_000),
    proxy_token: System.get_env("PROXY_TOKEN"),
    retry_base_ms: parse_integer.("PROXY_RETRY_BASE_MS", 25),
    retry_max_ms: parse_integer.("PROXY_RETRY_MAX_MS", 2_000)
end
