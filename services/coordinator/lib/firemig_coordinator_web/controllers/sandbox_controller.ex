defmodule FiremigCoordinatorWeb.SandboxController do
  use FiremigCoordinatorWeb, :controller

  alias FiremigCoordinator.Sandboxes
  alias FiremigCoordinatorWeb.ControlJSON

  action_fallback FiremigCoordinatorWeb.FallbackController

  def create(conn, params) do
    with {:ok, sandbox} <- Sandboxes.create(params) do
      conn
      |> put_status(:created)
      |> json(render_sandbox(sandbox))
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, sandbox} <- Sandboxes.get(id) do
      json(conn, render_sandbox(sandbox))
    end
  end

  defp render_sandbox(sandbox) do
    ControlJSON.sandbox(
      sandbox,
      Sandboxes.ports(sandbox.id),
      Sandboxes.last_migration(sandbox.id)
    )
  end
end
