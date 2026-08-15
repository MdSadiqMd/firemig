defmodule FiremigCoordinatorWeb.SandboxControlController do
  use FiremigCoordinatorWeb, :controller

  alias FiremigCoordinator.Sandboxes
  alias FiremigCoordinatorWeb.ControlJSON

  action_fallback FiremigCoordinatorWeb.FallbackController

  def command(conn, %{"id" => id} = params) do
    attrs = Map.delete(params, "id")

    with {:ok, result} <- Sandboxes.run_command(id, attrs) do
      conn
      |> put_status(command_status(result))
      |> json(result)
    end
  end

  def file(conn, %{"id" => id} = params) do
    with {:ok, result} <- Sandboxes.write_file(id, Map.delete(params, "id")) do
      json(conn, result)
    end
  end

  def port(conn, %{"id" => id} = params) do
    with {:ok, port, disposition} <- Sandboxes.expose_port(id, Map.delete(params, "id")) do
      conn
      |> put_status(port_status(disposition))
      |> json(ControlJSON.port(port))
    end
  end

  defp command_status(%{"pid" => _pid}), do: :accepted
  defp command_status(_result), do: :ok

  defp port_status(:created), do: :created
  defp port_status(:replay), do: :ok
end
