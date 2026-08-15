import Config

if System.get_env("PHX_SERVER") do
  config :firemig_coordinator, FiremigCoordinatorWeb.Endpoint, server: true
end

config :firemig_coordinator, FiremigCoordinatorWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

worker_urls =
  System.get_env("WORKER_URLS", "worker-a=http://127.0.0.1:4101,worker-b=http://127.0.0.1:4102")
  |> String.split(",", trim: true)
  |> Map.new(fn entry ->
    [worker, url] = String.split(entry, "=", parts: 2)
    {worker, url}
  end)

config :firemig_coordinator,
  api_token: System.get_env("API_TOKEN"),
  redpanda_http_url: System.get_env("REDPANDA_HTTP_URL", "http://127.0.0.1:8082"),
  worker_urls: worker_urls,
  worker_token: System.get_env("WORKER_TOKEN"),
  proxy_url: System.get_env("PROXY_URL", "http://127.0.0.1:4200"),
  proxy_token: System.get_env("PROXY_TOKEN"),
  proxy_public_host: System.get_env("PROXY_PUBLIC_HOST", "127.0.0.1"),
  default_proxy_port: String.to_integer(System.get_env("DEFAULT_PROXY_PORT", "8080"))

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/firemig_coordinator/firemig_coordinator.db
      """

  config :firemig_coordinator, FiremigCoordinator.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5"),
    journal_mode: :wal,
    default_transaction_mode: :immediate,
    busy_timeout: 5_000

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :firemig_coordinator, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :firemig_coordinator, FiremigCoordinatorWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    secret_key_base: secret_key_base
end
