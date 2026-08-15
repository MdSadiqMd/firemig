import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :firemig_coordinator, FiremigCoordinator.Repo,
  database: Path.expand("../firemig_coordinator_test.db", __DIR__),
  pool_size: 5,
  journal_mode: :wal,
  default_transaction_mode: :immediate,
  busy_timeout: 5_000,
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :firemig_coordinator, FiremigCoordinatorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "HEKIm68/gPCTVmVPdndSgKRNdjZIMxyezwbRkNfpZaBUeugbh73jgudH8KM5kCnA",
  server: false

config :firemig_coordinator,
  command_queue: FiremigCoordinator.MockCommandQueue,
  redpanda_http_url: "http://redpanda.test"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
