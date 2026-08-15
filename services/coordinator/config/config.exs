# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :firemig_coordinator,
  ecto_repos: [FiremigCoordinator.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  api_token: nil,
  command_queue: FiremigCoordinator.CommandQueue.RedpandaHTTP,
  command_queue_topic: "firemig.commands",
  redpanda_http_url: "http://127.0.0.1:8082",
  redpanda_max_bytes: 1_048_576,
  redpanda_req_options: [],
  worker_client: FiremigCoordinator.WorkerClient.Req,
  proxy_client: FiremigCoordinator.ProxyClient.Req,
  worker_urls: %{
    "worker-a" => "http://127.0.0.1:4101",
    "worker-b" => "http://127.0.0.1:4102"
  },
  worker_token: nil,
  worker_req_options: [],
  proxy_url: "http://127.0.0.1:4200",
  proxy_token: nil,
  proxy_req_options: [],
  proxy_public_host: "127.0.0.1"

# Configure the endpoint
config :firemig_coordinator, FiremigCoordinatorWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: FiremigCoordinatorWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FiremigCoordinator.PubSub,
  live_view: [signing_salt: "0xaoZcCQ"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
