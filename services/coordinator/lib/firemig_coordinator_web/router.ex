defmodule FiremigCoordinatorWeb.Router do
  use FiremigCoordinatorWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug FiremigCoordinatorWeb.ApiAuth
  end

  pipeline :sse do
    plug FiremigCoordinatorWeb.ApiAuth
  end

  get "/healthz", FiremigCoordinatorWeb.HealthController, :show

  scope "/v1", FiremigCoordinatorWeb do
    pipe_through :api

    post "/sandboxes", SandboxController, :create
    get "/sandboxes/:id", SandboxController, :show
    post "/sandboxes/:id/commands", SandboxControlController, :command
    put "/sandboxes/:id/files", SandboxControlController, :file
    post "/sandboxes/:id/ports", SandboxControlController, :port
    post "/sandboxes/:id/migrations", MigrationController, :create
    get "/sandboxes/:id/migrations/:migration_id", MigrationController, :show
  end

  scope "/v1", FiremigCoordinatorWeb do
    pipe_through :sse

    get "/sandboxes/:id/migrations/:migration_id/events", MigrationController, :events
  end

  if Application.compile_env(:firemig_coordinator, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: FiremigCoordinatorWeb.Telemetry
    end
  end
end
