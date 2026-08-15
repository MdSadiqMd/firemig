defmodule FiremigCoordinator.Repo do
  use Ecto.Repo,
    otp_app: :firemig_coordinator,
    adapter: Ecto.Adapters.SQLite3
end
