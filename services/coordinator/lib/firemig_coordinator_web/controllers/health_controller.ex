defmodule FiremigCoordinatorWeb.HealthController do
  use FiremigCoordinatorWeb, :controller

  alias FiremigCoordinator.Health

  def show(conn, _params) do
    case Health.readiness() do
      {:ok, checks} ->
        json(conn, %{status: "ok", checks: checks})

      {:error, checks} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "not_ready", checks: checks})
    end
  end
end
