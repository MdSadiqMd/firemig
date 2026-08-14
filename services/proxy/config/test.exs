import Config

config :firemig_proxy,
  admin_port: 0,
  listener_ip: {127, 0, 0, 1},
  num_acceptors: 1

config :logger, level: :warning
