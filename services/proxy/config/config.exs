import Config

config :firemig_proxy,
  admin_ip: {127, 0, 0, 1},
  admin_port: 4001,
  buffer_bytes: 262_144,
  connect_timeout_ms: 1_000,
  internal_send_timeout_ms: 5_000,
  listener_ip: {0, 0, 0, 0},
  num_acceptors: 10,
  proxy_token: nil,
  retry_base_ms: 25,
  retry_max_ms: 2_000

import_config "#{config_env()}.exs"
